/**
 * @file    test_mbwb_esp.c
 * @brief   Self-test and echo application for the MBWB ESP32 UART link.
 *
 * @date    17-Nov-2026
 * @version 1.0
 *
 * @detail
 * Part 1 - self-test (no ESP32 needed). Uses the peripheral's internal
 * loopback to check:
 *   1. ID, FIFO sizes, and baud-rate divider
 *   2. a short message, polled
 *   3. a 20 KB stream, polled, 4-byte bus transfers
 *   4. a 20 KB stream and a short message, interrupt-driven
 *   5. software ring overflow handling (RX interrupt pause/resume)
 *
 * Part 2 - link mode (ESP32 connected to Pmod JB). Loopback is turned off and
 * every line received from the ESP32 is printed on the USB-UART terminal and
 * echoed back to the ESP32 as "FPGA got <n> bytes: <line>". A partial line is
 * also printed after TEST_ESP_LINE_IDLE_MS with no new data, so firmware that
 * does not send a newline still works.
 *
 * The ESP32 firmware must use the same baud rate (TEST_ESP_LINK_BAUD), 8N1,
 * and must enable RTS/CTS flow control if TEST_ESP_FLOW_CONTROL is 1.
 *
 * Wiring (provisional, see the constraints file):
 *   JB4 ESP_TXD  -> ESP32 RX      JB10 ESP_RXD   <- ESP32 TX
 *   JB3 ESP_RTS_N-> ESP32 CTS     JB9  ESP_CTS_N <- ESP32 RTS
 *   GND          -- ESP32 GND     (power the ESP32 from its own USB)
 */
/* SPDX-License-Identifier: MIT */

#include "MBWB_ESP.h"
#include "MBWB_HW.h"

#include "sleep.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "xstatus.h"
#include "xinterrupt_wrap.h"
#include "xparameters.h"

#include <stdbool.h>

/* -------------------------------------------------------------------------- */
/*  Test configuration                                                        */
/* -------------------------------------------------------------------------- */

#define TEST_ESP_SELFTEST_BAUD     MBWB_ESP_BAUD_2M
#define TEST_ESP_LINK_BAUD         MBWB_ESP_BAUD_115200   /* must match the ESP32 */
#define TEST_ESP_FLOW_CONTROL      0      /* 1 only if the ESP32 uses RTS/CTS too */
#define TEST_ESP_STREAM_BYTES      20000U
#define TEST_ESP_LINE_MAX          256U
#define TEST_ESP_LINE_IDLE_MS      50U

/*
 * The ESP UART shares the AXI interrupt controller with the timers; use the
 * BSP-generated interrupt-parent encoding (same approach as the MBWB demos).
 */
#if defined(XPAR_XTMRCTR_1_INTERRUPT_PARENT)
#define TEST_ESP_INTERRUPT_PARENT  XPAR_XTMRCTR_1_INTERRUPT_PARENT
#elif defined(XPAR_XTMRCTR_0_INTERRUPT_PARENT)
#define TEST_ESP_INTERRUPT_PARENT  XPAR_XTMRCTR_0_INTERRUPT_PARENT
#else
#error "Cannot find the interrupt-controller parent in xparameters.h"
#endif

/* -------------------------------------------------------------------------- */
/*  Private data and helper prototypes                                        */
/* -------------------------------------------------------------------------- */

static u8  TxBuf[TEST_ESP_STREAM_BYTES];
static u8  RxBuf[TEST_ESP_STREAM_BYTES];
static u32 TestsRun;
static u32 TestsFailed;

static void TEST_ESP_check(bool Passed, const char *What);
static void TEST_ESP_fillPattern(u8 *Buffer, u32 Length, u32 Seed);
static bool TEST_ESP_compare(const u8 *A, const u8 *B, u32 Length);
static u32  TEST_ESP_transfer(u32 TxLength, u32 RxLength);
static u32  TEST_ESP_stream(u32 Length);
static void TEST_ESP_registers(void);
static void TEST_ESP_shortPolled(void);
static void TEST_ESP_streamPolled(void);
static void TEST_ESP_interrupt(void);
static void TEST_ESP_ringOverflow(void);
static void TEST_ESP_linkMode(void);

/* -------------------------------------------------------------------------- */
/*  Main application                                                          */
/* -------------------------------------------------------------------------- */

int main(void)
{
    int Status;

    xil_printf("\r\n");
    xil_printf("MBWB ESP32 UART link test\r\n");
    xil_printf("--------------------------------------------------\r\n");
    xil_printf("Initializing the ESP driver at 0x%08lx...\r\n",
               (unsigned long)MBWB_ESP_BASEADDR);

    Status = MBWB_ESP_initialize(MBWB_ESP_BASEADDR, TEST_ESP_SELFTEST_BAUD);

    if (Status != XST_SUCCESS)
    {
        xil_printf("ERROR: ESP peripheral not found (ID register mismatch)\r\n");
        xil_printf("       Is the 512K bridge range / new bitstream loaded?\r\n");
        return XST_FAILURE;
    }

    xil_printf("FIFOs: RX %u bytes, TX %u bytes\r\n",
               (unsigned)MBWB_ESP_getRxFifoSize(), (unsigned)MBWB_ESP_getTxFifoSize());

    Status = XSetupInterruptSystem(NULL,
                                   (XInterruptHandler)MBWB_ESP_interruptHandler,
                                   MBWB_ESP_INTERRUPT_ID,
                                   TEST_ESP_INTERRUPT_PARENT,
                                   XINTERRUPT_DEFAULT_PRIORITY);

    if (Status != XST_SUCCESS)
    {
        xil_printf("ERROR: could not connect the ESP interrupt (ID %u)\r\n",
                   (unsigned)MBWB_ESP_INTERRUPT_ID);
        return XST_FAILURE;
    }

    /* ---------------- Part 1: self-test in internal loopback ---------------- */
    xil_printf("\r\nPart 1: self-test (internal loopback, no ESP32 needed)\r\n");

    TEST_ESP_registers();

    MBWB_ESP_setLoopback(true);
    TEST_ESP_shortPolled();
    TEST_ESP_streamPolled();
    TEST_ESP_interrupt();
    TEST_ESP_ringOverflow();
    MBWB_ESP_setLoopback(false);

    xil_printf("\r\nSelf-test: %u checks, %u failed -> %s\r\n",
               (unsigned)TestsRun, (unsigned)TestsFailed,
               (TestsFailed == 0U) ? "PASSED" : "FAILED");

    /* ---------------- Part 2: talk to the ESP32 ---------------- */
    TEST_ESP_linkMode();        /* does not return */

    return XST_SUCCESS;
}

/* -------------------------------------------------------------------------- */
/*  Helpers                                                                   */
/* -------------------------------------------------------------------------- */

static void TEST_ESP_check(bool Passed, const char *What)
{
    TestsRun++;

    if (!Passed)
    {
        TestsFailed++;
    }

    xil_printf("  [%s] %s\r\n", Passed ? "PASS" : "FAIL", What);
}

/* Deterministic pseudo-random bytes (xorshift32). */
static void TEST_ESP_fillPattern(u8 *Buffer, u32 Length, u32 Seed)
{
    u32 X = (Seed != 0U) ? Seed : 1U;
    u32 I;

    for (I = 0U; I < Length; I++)
    {
        X ^= X << 13;
        X ^= X >> 17;
        X ^= X << 5;
        Buffer[I] = (u8)X;
    }
}

static bool TEST_ESP_compare(const u8 *A, const u8 *B, u32 Length)
{
    u32 I;

    for (I = 0U; I < Length; I++)
    {
        if (A[I] != B[I])
        {
            xil_printf("    first mismatch at byte %u: sent 0x%02x, got 0x%02x\r\n",
                       (unsigned)I, (unsigned)A[I], (unsigned)B[I]);
            return false;
        }
    }

    return true;
}

/*
 * Send TxBuf[0..TxLength) (may be 0) while receiving RxLength bytes into
 * RxBuf. The stream is larger than the RX FIFO, so it must be read while it
 * is being sent. Gives up after TEST_ESP_IDLE_TIMEOUT_US with no progress.
 * Returns the number of bytes received.
 */
#define TEST_ESP_IDLE_TIMEOUT_US   500000U
#define TEST_ESP_IDLE_STEP_US      10U

static u32 TEST_ESP_transfer(u32 TxLength, u32 RxLength)
{
    u32 Sent   = 0U;
    u32 Rcvd   = 0U;
    u32 IdleUs = 0U;

    while ((Rcvd < RxLength) && (IdleUs < TEST_ESP_IDLE_TIMEOUT_US))
    {
        u32 Progress = 0U;

        if (Sent < TxLength)
        {
            u32 N = MBWB_ESP_tryWrite(&TxBuf[Sent], TxLength - Sent);
            Sent += N;
            Progress += N;
        }

        {
            u32 N = MBWB_ESP_read(&RxBuf[Rcvd], RxLength - Rcvd);
            Rcvd += N;
            Progress += N;
        }

        if (Progress == 0U)
        {
            usleep(TEST_ESP_IDLE_STEP_US);
            IdleUs += TEST_ESP_IDLE_STEP_US;
        }
        else
        {
            IdleUs = 0U;
        }
    }

    return Rcvd;
}

static u32 TEST_ESP_stream(u32 Length)
{
    return TEST_ESP_transfer(Length, Length);
}

/* -------------------------------------------------------------------------- */
/*  Part 1 tests                                                              */
/* -------------------------------------------------------------------------- */

/***** 1. Registers and baud rate *****/
static void TEST_ESP_registers(void)
{
    xil_printf("Test 1: registers\r\n");

    TEST_ESP_check(MBWB_ESP_getRxFifoSize() == 4096U && MBWB_ESP_getTxFifoSize() == 1024U,
                   "FIFO sizes 4096 / 1024");

    TEST_ESP_check(MBWB_ESP_setBaudRate(MBWB_ESP_BAUD_115200) == XST_SUCCESS &&
                   MBWB_ESP_getBaudRate() == 115207U,
                   "115200 baud -> divider 868 (115207, +0.006%)");

    TEST_ESP_check(MBWB_ESP_setBaudRate(100U) == XST_INVALID_PARAM,
                   "100 baud rejected (divider too large)");

    TEST_ESP_check(MBWB_ESP_setBaudRate(TEST_ESP_SELFTEST_BAUD) == XST_SUCCESS &&
                   MBWB_ESP_getBaudRate() == TEST_ESP_SELFTEST_BAUD,
                   "2 Mbaud -> divider 50 (exact)");

    TEST_ESP_check(MBWB_ESP_getErrors() == 0U && MBWB_ESP_isTxIdle() &&
                   MBWB_ESP_rxAvailable() == 0U,
                   "idle, empty, no errors after init");
}

/***** 2. Short message, polled *****/
static void TEST_ESP_shortPolled(void)
{
    static const char Msg[] = "Hello from the MicroBlaze!";
    const u32 Len = sizeof(Msg) - 1U;
    u32 Got;

    xil_printf("Test 2: short message, polled\r\n");

    MBWB_ESP_writeString(Msg);
    MBWB_ESP_waitTxIdle();
    usleep(100U);

    TEST_ESP_check(MBWB_ESP_rxAvailable() == Len, "all bytes looped back");

    Got = MBWB_ESP_read(RxBuf, sizeof(RxBuf));
    TEST_ESP_check(Got == Len && TEST_ESP_compare((const u8 *)Msg, RxBuf, Len),
                   "data matches");
    TEST_ESP_check(MBWB_ESP_readByte() == -1, "nothing left to read");
}

/***** 3. Large stream, polled *****/
static void TEST_ESP_streamPolled(void)
{
    u32 Got;

    xil_printf("Test 3: %u-byte stream, polled\r\n", (unsigned)TEST_ESP_STREAM_BYTES);

    TEST_ESP_fillPattern(TxBuf, TEST_ESP_STREAM_BYTES, 0x1234U);
    Got = TEST_ESP_stream(TEST_ESP_STREAM_BYTES);

    TEST_ESP_check(Got == TEST_ESP_STREAM_BYTES, "all bytes received");
    TEST_ESP_check(TEST_ESP_compare(TxBuf, RxBuf, Got), "data matches");
    TEST_ESP_check(MBWB_ESP_getErrors() == 0U, "no overrun / framing errors");
}

/***** 4. Interrupt-driven receive *****/
static void TEST_ESP_interrupt(void)
{
    static const char Msg[] = "short";
    u32 Got;
    u32 IntrBefore;

    xil_printf("Test 4: interrupt-driven receive\r\n");

    MBWB_ESP_setRxInterruptConfig(MBWB_ESP_DEFAULT_RX_THRESHOLD, MBWB_ESP_DEFAULT_RX_TIMEOUT);
    MBWB_ESP_enableRxInterrupt(true);
    IntrBefore = MBWB_ESP_getInterruptCount();

    TEST_ESP_fillPattern(TxBuf, TEST_ESP_STREAM_BYTES, 0xBEEFU);
    Got = TEST_ESP_stream(TEST_ESP_STREAM_BYTES);

    TEST_ESP_check(Got == TEST_ESP_STREAM_BYTES, "stream: all bytes received");
    TEST_ESP_check(TEST_ESP_compare(TxBuf, RxBuf, Got), "stream: data matches");
    TEST_ESP_check(MBWB_ESP_getInterruptCount() > IntrBefore, "stream: interrupts taken");

    /* 5 bytes is below the 64-byte threshold: delivered by the idle timeout. */
    IntrBefore = MBWB_ESP_getInterruptCount();
    MBWB_ESP_writeString(Msg);
    MBWB_ESP_waitTxIdle();
    usleep(1000U);

    TEST_ESP_check(MBWB_ESP_getInterruptCount() > IntrBefore &&
                   MBWB_ESP_rxAvailable() == (sizeof(Msg) - 1U),
                   "short message delivered by the idle timeout");

    Got = MBWB_ESP_read(RxBuf, sizeof(RxBuf));
    TEST_ESP_check(Got == (sizeof(Msg) - 1U) &&
                   TEST_ESP_compare((const u8 *)Msg, RxBuf, Got),
                   "short message data matches");
    TEST_ESP_check(MBWB_ESP_getErrors() == 0U, "no errors");
}

/***** 5. Software ring overflow: pause and resume *****/
static void TEST_ESP_ringOverflow(void)
{
    const u32 Len = MBWB_ESP_RX_RING_SIZE + 2000U;   /* ring + part of the HW FIFO */
    u32 Got;

    xil_printf("Test 5: %u bytes without reading (ring full -> pause/resume)\r\n",
               (unsigned)Len);

    TEST_ESP_fillPattern(TxBuf, Len, 0x5555U);
    MBWB_ESP_write(TxBuf, Len);
    MBWB_ESP_waitTxIdle();
    usleep(1000U);

    TEST_ESP_check(MBWB_ESP_rxAvailable() == MBWB_ESP_RX_RING_SIZE,
                   "ring full, remainder held in the hardware FIFO");

    Got = TEST_ESP_transfer(0U, Len);       /* receive only */

    TEST_ESP_check(Got == Len && TEST_ESP_compare(TxBuf, RxBuf, Len),
                   "all bytes received in order after resume");
    TEST_ESP_check(MBWB_ESP_getErrors() == 0U, "no overrun");

    MBWB_ESP_enableRxInterrupt(false);
}

/* -------------------------------------------------------------------------- */
/*  Part 2: link mode                                                         */
/* -------------------------------------------------------------------------- */

/* Print a received line (non-printable bytes as <xx>) and echo it back. */
static void TEST_ESP_handleLine(const u8 *Line, u32 Length)
{
    static u32 LineCount = 0U;
    char Number[12];
    u32  I;
    u32  N;
    u32  Pos;

    LineCount++;
    xil_printf("[ESP32 -> FPGA] #%u (%u bytes): ", (unsigned)LineCount, (unsigned)Length);

    for (I = 0U; I < Length; I++)
    {
        if ((Line[I] >= 0x20U) && (Line[I] < 0x7FU))
        {
            xil_printf("%c", Line[I]);
        }
        else
        {
            xil_printf("<%02x>", (unsigned)Line[I]);
        }
    }

    xil_printf("\r\n");

    /* Reply: "FPGA got <n> bytes: <line>\r\n" */
    N = Length;
    Pos = sizeof(Number) - 1U;
    Number[Pos] = '\0';
    do
    {
        Number[--Pos] = (char)('0' + (N % 10U));
        N /= 10U;
    } while ((N != 0U) && (Pos > 0U));

    MBWB_ESP_writeString("FPGA got ");
    MBWB_ESP_writeString(&Number[Pos]);
    MBWB_ESP_writeString(" bytes: ");
    MBWB_ESP_write(Line, Length);
    MBWB_ESP_writeString("\r\n");
}

static void TEST_ESP_linkMode(void)
{
    static u8 Line[TEST_ESP_LINE_MAX];
    u32 LineLen = 0U;
    u32 IdleMs  = 0U;
    u32 Errors;
    u8  Chunk[64];

    (void)MBWB_ESP_setBaudRate(TEST_ESP_LINK_BAUD);
    MBWB_ESP_enableFlowControl(TEST_ESP_FLOW_CONTROL != 0);
    MBWB_ESP_flushRx();
    MBWB_ESP_clearErrors(MBWB_ESP_ERR_ALL);
    MBWB_ESP_setRxInterruptConfig(MBWB_ESP_DEFAULT_RX_THRESHOLD, MBWB_ESP_DEFAULT_RX_TIMEOUT);
    MBWB_ESP_enableRxInterrupt(true);

    xil_printf("\r\nPart 2: link mode - %u baud, 8N1, flow control %s\r\n",
               (unsigned)MBWB_ESP_getBaudRate(), TEST_ESP_FLOW_CONTROL ? "ON" : "OFF");
    xil_printf("Type into the ESP32's serial monitor; each line is shown here\r\n");
    xil_printf("and echoed back to the ESP32.\r\n\r\n");

    MBWB_ESP_writeString("FPGA ready\r\n");

    for (;;)
    {
        u32 Got = MBWB_ESP_read(Chunk, sizeof(Chunk));
        u32 I;

        if (Got == 0U)
        {
            usleep(1000U);
            IdleMs++;

            /* Flush a partial line once the sender has gone quiet. */
            if ((LineLen > 0U) && (IdleMs >= TEST_ESP_LINE_IDLE_MS))
            {
                TEST_ESP_handleLine(Line, LineLen);
                LineLen = 0U;
            }
        }
        else
        {
            IdleMs = 0U;
        }

        for (I = 0U; I < Got; I++)
        {
            u8 C = Chunk[I];

            if ((C == '\r') || (C == '\n'))
            {
                if (LineLen > 0U)
                {
                    TEST_ESP_handleLine(Line, LineLen);
                    LineLen = 0U;
                }
            }
            else
            {
                Line[LineLen++] = C;

                if (LineLen == TEST_ESP_LINE_MAX)
                {
                    TEST_ESP_handleLine(Line, LineLen);
                    LineLen = 0U;
                }
            }
        }

        Errors = MBWB_ESP_getErrors();
        if (Errors != 0U)
        {
            xil_printf("[link error]%s%s - check baud rate / wiring / flow control\r\n",
                       (Errors & MBWB_ESP_ERR_OVERRUN) ? " RX overrun" : "",
                       (Errors & MBWB_ESP_ERR_FRAME)   ? " framing" : "");
            MBWB_ESP_clearErrors(Errors);
        }
    }
}
