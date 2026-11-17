/**
 * @file    MBWB_ESP.c
 * @brief   Driver for the MBWB ESP32 UART link (wb_esp Wishbone peripheral).
 *
 * @date    17-Nov-2026
 * @version 1.0
 *
 * @detail
 * See MBWB_ESP.h for the API description.
 *
 * Interrupt-mode design notes:
 *
 *   - The software ring buffer has a single producer (the interrupt handler)
 *     and a single consumer (the read functions). The head and tail indices
 *     are free-running 32-bit counters, each written by only one side, so no
 *     locking is needed for the data path.
 *
 *   - The interrupt input is rising-edge sensitive. The handler therefore
 *     empties the hardware RX FIFO before returning so the IRQ line drops and
 *     the next arrival produces a new edge. When the ring is full the handler
 *     instead clears RX_IRQ_EN (the line drops) and sets RxIrqPaused; the
 *     read functions set RX_IRQ_EN again once half the ring is free, which
 *     produces a new edge if data is still waiting.
 *
 *   - CTRL is written from both the handler (pause) and the application, so
 *     application-side CTRL updates run with interrupts disabled.
 *
 *   - Transmit checks TX FIFO space before every write. The hardware would
 *     otherwise hold the bus ACK until space frees up, which could stall the
 *     CPU (and every interrupt) indefinitely while the ESP32 holds CTS off.
 */
/* SPDX-License-Identifier: MIT */

#include "MBWB_ESP.h"

#include "mb_interface.h"
#include "sleep.h"

#include <stddef.h>

/* -------------------------------------------------------------------------- */
/*  Private definitions                                                       */
/* -------------------------------------------------------------------------- */

#define ESP_MSR_IE              0x00000002U     /* MicroBlaze MSR interrupt enable */
#define ESP_RING_MASK           (MBWB_ESP_RX_RING_SIZE - 1U)
#define ESP_POLL_STEP_US        10U

/* -------------------------------------------------------------------------- */
/*  Private state                                                             */
/* -------------------------------------------------------------------------- */

static UINTPTR EspBase;
static u32     CtrlShadow;          /* persistent CTRL bits (never the flush bits) */
static u32     RxFifoSize;
static u32     TxFifoSize;

static volatile bool RxIntrMode;
static volatile bool RxIrqPaused;
static volatile u32  RxHead;        /* written only by the interrupt handler */
static volatile u32  RxTail;        /* written only by the read functions    */
static volatile u32  IntrCount;
static u8            RxRing[MBWB_ESP_RX_RING_SIZE];

static MBWB_ESP_RxCallback RxCallback;
static void               *RxCallbackRef;

/* -------------------------------------------------------------------------- */
/*  Private helpers                                                           */
/* -------------------------------------------------------------------------- */

static inline u32 ESP_readReg(u32 RegIndex)
{
    return MBWB_L_readReg(EspBase, RegIndex);
}

static inline void ESP_writeReg(u32 RegIndex, u32 Data)
{
    MBWB_L_writeReg(EspBase, RegIndex, Data);
}

static inline u32 ESP_rxLevel(void)
{
    return ESP_readReg(MBWB_ESP_LEVEL_REG) & MBWB_ESP_RX_FIELD_MASK;
}

static inline u32 ESP_txLevel(void)
{
    return ESP_readReg(MBWB_ESP_LEVEL_REG) >> MBWB_ESP_TX_FIELD_SHIFT;
}

/* Disable interrupts, returning the previous MSR so the state can be restored. */
static inline u32 ESP_enterCritical(void)
{
    u32 Msr = mfmsr();
    microblaze_disable_interrupts();
    return Msr;
}

static inline void ESP_exitCritical(u32 Msr)
{
    if ((Msr & ESP_MSR_IE) != 0U)
    {
        microblaze_enable_interrupts();
    }
}

/* Set/clear persistent CTRL bits and write CTRL (plus one-shot bits). */
static void ESP_updateCtrl(u32 SetMask, u32 ClearMask, u32 PulseMask)
{
    u32 Msr = ESP_enterCritical();

    CtrlShadow = (CtrlShadow & ~ClearMask) | SetMask;
    ESP_writeReg(MBWB_ESP_CTRL_REG, CtrlShadow | PulseMask);

    ESP_exitCritical(Msr);
}

static u32 ESP_baudDivider(u32 BaudRate)
{
    if (BaudRate == 0U)
    {
        return 0U;
    }

    /* Rounded; MBWB_ESP_CLOCK_HZ + BaudRate/2 stays well inside 32 bits. */
    return (MBWB_ESP_CLOCK_HZ + (BaudRate / 2U)) / BaudRate;
}

/* Number of bytes in the software ring. */
static inline u32 ESP_ringCount(void)
{
    return RxHead - RxTail;
}

/* Resume a paused RX interrupt once the application has drained half the ring. */
static void ESP_maybeResumeRxIrq(void)
{
    if (RxIrqPaused &&
        ((MBWB_ESP_RX_RING_SIZE - ESP_ringCount()) >= (MBWB_ESP_RX_RING_SIZE / 2U)))
    {
        u32 Msr = ESP_enterCritical();

        if (RxIrqPaused && RxIntrMode)
        {
            RxIrqPaused = false;
            CtrlShadow |= MBWB_ESP_CTRL_RX_IRQ_EN_MASK;
            ESP_writeReg(MBWB_ESP_CTRL_REG, CtrlShadow);
        }

        ESP_exitCritical(Msr);
    }
}

/* Copy bytes out of the software ring. */
static u32 ESP_ringRead(u8 *Buffer, u32 MaxLength)
{
    u32 Head = RxHead;
    u32 Tail = RxTail;
    u32 Count = 0U;

    while ((Tail != Head) && (Count < MaxLength))
    {
        Buffer[Count] = RxRing[Tail & ESP_RING_MASK];
        Tail++;
        Count++;
    }

    RxTail = Tail;

    if (Count != 0U)
    {
        ESP_maybeResumeRxIrq();
    }

    return Count;
}

/* Copy bytes straight out of the hardware RX FIFO (polled mode only). */
static u32 ESP_hwRead(u8 *Buffer, u32 MaxLength)
{
    u32 Count = 0U;

    while (Count < MaxLength)
    {
        u32 Level = ESP_rxLevel();

        if (Level == 0U)
        {
            break;
        }

        while ((Level >= 4U) && ((MaxLength - Count) >= 4U))
        {
            u32 Word = ESP_readReg(MBWB_ESP_RXDATA32_REG);

            Buffer[Count]      = (u8)Word;
            Buffer[Count + 1U] = (u8)(Word >> 8);
            Buffer[Count + 2U] = (u8)(Word >> 16);
            Buffer[Count + 3U] = (u8)(Word >> 24);
            Count += 4U;
            Level -= 4U;
        }

        while ((Level > 0U) && (Count < MaxLength))
        {
            Buffer[Count] = (u8)ESP_readReg(MBWB_ESP_RXDATA_REG);
            Count++;
            Level--;
        }
    }

    return Count;
}

/* -------------------------------------------------------------------------- */
/*  Initialization and configuration                                          */
/* -------------------------------------------------------------------------- */

/***** MBWB_ESP_initialize() - Verify the peripheral and reset the link. *****/
int MBWB_ESP_initialize(UINTPTR BaseAddress, u32 BaudRate)
{
    u32 FifoSizes;

    EspBase = BaseAddress;

    if (ESP_readReg(MBWB_ESP_ID_REG) != MBWB_ESP_ID_VALUE)
    {
        return XST_DEVICE_NOT_FOUND;
    }

    /* Everything off, both FIFOs emptied. */
    CtrlShadow    = 0U;
    RxIntrMode    = false;
    RxIrqPaused   = false;
    RxHead        = 0U;
    RxTail        = 0U;
    IntrCount     = 0U;
    RxCallback    = NULL;
    RxCallbackRef = NULL;
    ESP_writeReg(MBWB_ESP_CTRL_REG,
                 MBWB_ESP_CTRL_RX_FLUSH_MASK | MBWB_ESP_CTRL_TX_FLUSH_MASK);

    FifoSizes  = ESP_readReg(MBWB_ESP_FIFOSZ_REG);
    RxFifoSize = FifoSizes & MBWB_ESP_RX_FIELD_MASK;
    TxFifoSize = FifoSizes >> MBWB_ESP_TX_FIELD_SHIFT;

    MBWB_ESP_setRxInterruptConfig(MBWB_ESP_DEFAULT_RX_THRESHOLD,
                                  MBWB_ESP_DEFAULT_RX_TIMEOUT);
    ESP_writeReg(MBWB_ESP_TXTHRESH_REG, 0U);
    MBWB_ESP_clearErrors(MBWB_ESP_ERR_ALL);

    return MBWB_ESP_setBaudRate(BaudRate);
}

/***** MBWB_ESP_setBaudRate() - Program the baud-rate divider. *****/
int MBWB_ESP_setBaudRate(u32 BaudRate)
{
    u32 Divider = ESP_baudDivider(BaudRate);

    if ((Divider < MBWB_ESP_BAUDDIV_MIN) || (Divider > MBWB_ESP_BAUDDIV_MAX))
    {
        return XST_INVALID_PARAM;
    }

    ESP_writeReg(MBWB_ESP_BAUDDIV_REG, Divider);
    return XST_SUCCESS;
}

/***** MBWB_ESP_getBaudRate() - Actual baud rate from the divider. *****/
u32 MBWB_ESP_getBaudRate(void)
{
    u32 Divider = ESP_readReg(MBWB_ESP_BAUDDIV_REG) & MBWB_ESP_BAUDDIV_MAX;

    return (MBWB_ESP_CLOCK_HZ + (Divider / 2U)) / Divider;
}

/***** MBWB_ESP_enableFlowControl() *****/
void MBWB_ESP_enableFlowControl(bool Enable)
{
    if (Enable)
    {
        ESP_updateCtrl(MBWB_ESP_CTRL_FLOW_EN_MASK, 0U, 0U);
    }
    else
    {
        ESP_updateCtrl(0U, MBWB_ESP_CTRL_FLOW_EN_MASK, 0U);
    }
}

/***** MBWB_ESP_setLoopback() *****/
void MBWB_ESP_setLoopback(bool Enable)
{
    if (Enable)
    {
        ESP_updateCtrl(MBWB_ESP_CTRL_LOOPBACK_MASK, 0U, 0U);
    }
    else
    {
        ESP_updateCtrl(0U, MBWB_ESP_CTRL_LOOPBACK_MASK, 0U);
    }
}

/***** MBWB_ESP_getStatus() *****/
u32 MBWB_ESP_getStatus(void)
{
    return ESP_readReg(MBWB_ESP_STATUS_REG);
}

/***** MBWB_ESP_getErrors() *****/
u32 MBWB_ESP_getErrors(void)
{
    return ESP_readReg(MBWB_ESP_STATUS_REG) & MBWB_ESP_ERR_ALL;
}

/***** MBWB_ESP_clearErrors() - Error bits are write-one-to-clear. *****/
void MBWB_ESP_clearErrors(u32 Mask)
{
    ESP_writeReg(MBWB_ESP_STATUS_REG, Mask & MBWB_ESP_ERR_ALL);
}

u32 MBWB_ESP_getRxFifoSize(void)
{
    return RxFifoSize;
}

u32 MBWB_ESP_getTxFifoSize(void)
{
    return TxFifoSize;
}

/* -------------------------------------------------------------------------- */
/*  Transmit                                                                  */
/* -------------------------------------------------------------------------- */

/***** MBWB_ESP_txFree() *****/
u32 MBWB_ESP_txFree(void)
{
    return TxFifoSize - ESP_txLevel();
}

/***** MBWB_ESP_isTxIdle() *****/
bool MBWB_ESP_isTxIdle(void)
{
    return (ESP_readReg(MBWB_ESP_STATUS_REG) & MBWB_ESP_STATUS_TX_IDLE_MASK) != 0U;
}

/***** MBWB_ESP_waitTxIdle() *****/
void MBWB_ESP_waitTxIdle(void)
{
    while (!MBWB_ESP_isTxIdle())
    {
        /* spin */
    }
}

/***** MBWB_ESP_tryWrite() - Queue what fits now; 4 bytes per bus write. *****/
u32 MBWB_ESP_tryWrite(const u8 *Data, u32 Length)
{
    u32 Free  = MBWB_ESP_txFree();
    u32 Count = 0U;

    while ((Count < Length) && (Free > 0U))
    {
        if (((Length - Count) >= 4U) && (Free >= 4U))
        {
            u32 Word = (u32)Data[Count]
                     | ((u32)Data[Count + 1U] << 8)
                     | ((u32)Data[Count + 2U] << 16)
                     | ((u32)Data[Count + 3U] << 24);

            ESP_writeReg(MBWB_ESP_TXDATA32_REG, Word);
            Count += 4U;
            Free  -= 4U;
        }
        else
        {
            ESP_writeReg(MBWB_ESP_TXDATA_REG, (u32)Data[Count]);
            Count++;
            Free--;
        }
    }

    return Count;
}

/***** MBWB_ESP_write() - Queue everything, waiting for space as needed. *****/
void MBWB_ESP_write(const u8 *Data, u32 Length)
{
    while (Length > 0U)
    {
        u32 Sent = MBWB_ESP_tryWrite(Data, Length);

        Data   += Sent;
        Length -= Sent;
    }
}

/***** MBWB_ESP_writeByte() *****/
void MBWB_ESP_writeByte(u8 Byte)
{
    MBWB_ESP_write(&Byte, 1U);
}

/***** MBWB_ESP_writeString() *****/
void MBWB_ESP_writeString(const char *String)
{
    u32 Length = 0U;

    while (String[Length] != '\0')
    {
        Length++;
    }

    MBWB_ESP_write((const u8 *)String, Length);
}

/***** MBWB_ESP_flushTx() *****/
void MBWB_ESP_flushTx(void)
{
    ESP_updateCtrl(0U, 0U, MBWB_ESP_CTRL_TX_FLUSH_MASK);
}

/* -------------------------------------------------------------------------- */
/*  Receive                                                                   */
/* -------------------------------------------------------------------------- */

/***** MBWB_ESP_rxAvailable() *****/
u32 MBWB_ESP_rxAvailable(void)
{
    u32 Count = ESP_ringCount();

    if (!RxIntrMode)
    {
        Count += ESP_rxLevel();
    }

    return Count;
}

/***** MBWB_ESP_read() - Ring first (left over from interrupt mode), then FIFO. *****/
u32 MBWB_ESP_read(u8 *Buffer, u32 MaxLength)
{
    u32 Count = ESP_ringRead(Buffer, MaxLength);

    if (!RxIntrMode && (Count < MaxLength))
    {
        Count += ESP_hwRead(&Buffer[Count], MaxLength - Count);
    }

    return Count;
}

/***** MBWB_ESP_readByte() *****/
int MBWB_ESP_readByte(void)
{
    u8 Byte;

    if (MBWB_ESP_read(&Byte, 1U) == 1U)
    {
        return (int)Byte;
    }

    return -1;
}

/***** MBWB_ESP_readByteTimeout() *****/
bool MBWB_ESP_readByteTimeout(u8 *Byte, u32 TimeoutUs)
{
    u32 Waited = 0U;

    for (;;)
    {
        if (MBWB_ESP_read(Byte, 1U) == 1U)
        {
            return true;
        }

        if ((TimeoutUs != 0U) && (Waited >= TimeoutUs))
        {
            return false;
        }

        usleep(ESP_POLL_STEP_US);
        Waited += ESP_POLL_STEP_US;
    }
}

/***** MBWB_ESP_flushRx() *****/
void MBWB_ESP_flushRx(void)
{
    u32 Msr = ESP_enterCritical();

    ESP_writeReg(MBWB_ESP_CTRL_REG, CtrlShadow | MBWB_ESP_CTRL_RX_FLUSH_MASK);
    RxTail = RxHead;

    ESP_exitCritical(Msr);

    ESP_maybeResumeRxIrq();
}

/* -------------------------------------------------------------------------- */
/*  Interrupt-driven receive                                                  */
/* -------------------------------------------------------------------------- */

/***** MBWB_ESP_setRxInterruptConfig() *****/
void MBWB_ESP_setRxInterruptConfig(u32 Threshold, u32 TimeoutBits)
{
    /*
     * Keep the threshold well below the point where flow control holds the
     * ESP32 off (RX FIFO size - RTS margin); a threshold that can never be
     * reached would leave data waiting for the timeout.
     */
    u32 MaxThreshold = (RxFifoSize != 0U) ? (RxFifoSize / 2U) : 1U;

    if (Threshold == 0U)
    {
        Threshold = 1U;
    }
    if (Threshold > MaxThreshold)
    {
        Threshold = MaxThreshold;
    }
    if (TimeoutBits > 0xFFFFU)
    {
        TimeoutBits = 0xFFFFU;
    }

    ESP_writeReg(MBWB_ESP_RXTHRESH_REG, Threshold);
    ESP_writeReg(MBWB_ESP_RXTIMEOUT_REG, TimeoutBits);
}

/***** MBWB_ESP_enableRxInterrupt() *****/
void MBWB_ESP_enableRxInterrupt(bool Enable)
{
    u32 Msr = ESP_enterCritical();

    RxIntrMode  = Enable;
    RxIrqPaused = false;

    if (Enable)
    {
        CtrlShadow |= MBWB_ESP_CTRL_RX_IRQ_EN_MASK;
    }
    else
    {
        CtrlShadow &= ~MBWB_ESP_CTRL_RX_IRQ_EN_MASK;
    }

    ESP_writeReg(MBWB_ESP_CTRL_REG, CtrlShadow);

    ESP_exitCritical(Msr);
}

/***** MBWB_ESP_setRxCallback() *****/
void MBWB_ESP_setRxCallback(MBWB_ESP_RxCallback Callback, void *CallbackRef)
{
    u32 Msr = ESP_enterCritical();

    RxCallback    = Callback;
    RxCallbackRef = CallbackRef;

    ESP_exitCritical(Msr);
}

/***** MBWB_ESP_interruptHandler() - Drain the hardware FIFO into the ring. *****/
void MBWB_ESP_interruptHandler(void *CallbackRef)
{
    u32  Head  = RxHead;
    u32  Tail  = RxTail;
    bool Moved = false;

    (void)CallbackRef;
    IntrCount++;

    for (;;)
    {
        u32 Level = ESP_rxLevel();
        u32 Space = MBWB_ESP_RX_RING_SIZE - (Head - Tail);

        if (Level == 0U)
        {
            break;      /* FIFO empty: the IRQ line is low again */
        }

        if (Space == 0U)
        {
            /*
             * Ring full: stop the interrupt (drops the IRQ line) and leave the
             * rest in the hardware FIFO. The read functions resume it.
             */
            RxIrqPaused = true;
            CtrlShadow &= ~MBWB_ESP_CTRL_RX_IRQ_EN_MASK;
            ESP_writeReg(MBWB_ESP_CTRL_REG, CtrlShadow);
            break;
        }

        while ((Level >= 4U) && (Space >= 4U))
        {
            u32 Word = ESP_readReg(MBWB_ESP_RXDATA32_REG);

            RxRing[Head & ESP_RING_MASK] = (u8)Word;
            RxRing[(Head + 1U) & ESP_RING_MASK] = (u8)(Word >> 8);
            RxRing[(Head + 2U) & ESP_RING_MASK] = (u8)(Word >> 16);
            RxRing[(Head + 3U) & ESP_RING_MASK] = (u8)(Word >> 24);
            Head  += 4U;
            Level -= 4U;
            Space -= 4U;
        }

        while ((Level > 0U) && (Space > 0U))
        {
            RxRing[Head & ESP_RING_MASK] = (u8)ESP_readReg(MBWB_ESP_RXDATA_REG);
            Head++;
            Level--;
            Space--;
        }

        RxHead = Head;      /* publish after the bytes are in the ring */
        Moved  = true;
    }

    if (Moved && (RxCallback != NULL))
    {
        RxCallback(RxCallbackRef);
    }
}

/***** MBWB_ESP_getInterruptCount() *****/
u32 MBWB_ESP_getInterruptCount(void)
{
    return IntrCount;
}
