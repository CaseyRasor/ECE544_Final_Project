/**
 * @file    MBWB_ESP.h
 * @brief   Public API for the MBWB ESP32 UART link driver.
 *
 * @date    17-Nov-2026
 * @version 1.0
 *
 * @detail
 * This driver controls the wb_esp Wishbone peripheral (Wishbone region 4): a
 * UART with 4 KB RX / 1 KB TX hardware FIFOs and optional RTS/CTS flow
 * control, used to talk to an ESP32 acting as a Wi-Fi co-processor.
 *
 * The driver is a byte stream. Message framing (packets, CRC) belongs in a
 * layer above it.
 *
 * Two receive modes:
 *
 *   - Polled (default): MBWB_ESP_read() and friends read the hardware RX FIFO
 *     directly.
 *
 *   - Interrupt-driven: after MBWB_ESP_enableRxInterrupt(true), the
 *     interrupt handler MBWB_ESP_interruptHandler() moves received bytes from
 *     the hardware FIFO into a software ring buffer, and the read functions
 *     take bytes from that ring. Connect the handler to interrupt ID
 *     MBWB_ESP_INTERRUPT_ID (wb_irq2) with XSetupInterruptSystem().
 *
 *     The interrupt input is rising-edge sensitive, so the handler always
 *     empties the hardware FIFO before it returns. If the ring buffer fills,
 *     the handler pauses the RX interrupt and leaves data in the hardware
 *     FIFO (with flow control on, the ESP32 is then held off by RTS); the
 *     read functions resume it once the application has made room. No bytes
 *     are dropped by the driver.
 *
 * Transmit functions never stall the bus: they check for TX FIFO space before
 * writing and wait in software, so interrupts keep running even while the
 * ESP32 holds CTS off.
 *
 * Calls are not thread-safe. Under FreeRTOS, use the link from a single task
 * (the interrupt handler may run alongside it), or protect it with a mutex.
 *
 * Build-time options (define before including, or with -D compiler flags):
 *
 *   - MBWB_ESP_CLOCK_HZ (default 100000000): Wishbone clock, used for the
 *     baud-rate divider.
 *   - MBWB_ESP_RX_RING_SIZE (default 4096, must be a power of two): size of
 *     the software receive buffer used in interrupt mode.
 */
/* SPDX-License-Identifier: MIT */

#ifndef MBWB_ESP_H
#define MBWB_ESP_H

#include "MBWB_L.h"
#include "xil_types.h"
#include "xstatus.h"

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------------- */
/*  Build-time configuration                                                  */
/* -------------------------------------------------------------------------- */

#ifndef MBWB_ESP_CLOCK_HZ
#define MBWB_ESP_CLOCK_HZ           100000000U
#endif

#ifndef MBWB_ESP_RX_RING_SIZE
#define MBWB_ESP_RX_RING_SIZE       4096U
#endif

#if (MBWB_ESP_RX_RING_SIZE & (MBWB_ESP_RX_RING_SIZE - 1U)) != 0U
#error "MBWB_ESP_RX_RING_SIZE must be a power of two"
#endif

/* -------------------------------------------------------------------------- */
/*  Constants                                                                 */
/* -------------------------------------------------------------------------- */

/* Common baud rates. Rates that divide 100 MHz exactly have no error. */
#define MBWB_ESP_BAUD_115200        115200U     /* bring-up default */
#define MBWB_ESP_BAUD_921600        921600U
#define MBWB_ESP_BAUD_1M            1000000U
#define MBWB_ESP_BAUD_2M            2000000U    /* also exact on the ESP32 (80 MHz) */

/* Default RX interrupt settings (see MBWB_ESP_setRxInterruptConfig()). */
#define MBWB_ESP_DEFAULT_RX_THRESHOLD   64U     /* bytes */
#define MBWB_ESP_DEFAULT_RX_TIMEOUT     40U     /* bit times (~4 characters) */

/* Error flags returned by MBWB_ESP_getErrors(). */
#define MBWB_ESP_ERR_OVERRUN        MBWB_ESP_STATUS_OVERRUN_MASK    /* RX FIFO overflowed */
#define MBWB_ESP_ERR_FRAME          MBWB_ESP_STATUS_FRAME_ERR_MASK  /* bad stop bit */
#define MBWB_ESP_ERR_UNDERRUN       MBWB_ESP_STATUS_UNDERRUN_MASK   /* driver bug */
#define MBWB_ESP_ERR_ALL            MBWB_ESP_STATUS_ERROR_MASK

/** Optional callback run by the interrupt handler after it has moved data. */
typedef void (*MBWB_ESP_RxCallback)(void *CallbackRef);

/* -------------------------------------------------------------------------- */
/*  Initialization and configuration                                          */
/* -------------------------------------------------------------------------- */

/**
 * @brief Initialize the ESP32 UART link.
 *
 * Verifies the peripheral ID, empties both FIFOs, clears errors, and sets the
 * baud rate. Flow control, loopback, and interrupts start disabled.
 *
 * @param BaseAddress Peripheral base address (normally MBWB_ESP_BASEADDR).
 * @param BaudRate    Baud rate in bits per second.
 *
 * @return XST_SUCCESS, XST_DEVICE_NOT_FOUND if the ID register does not
 *         match, or XST_INVALID_PARAM if the baud rate is out of range.
 */
int MBWB_ESP_initialize(UINTPTR BaseAddress, u32 BaudRate);

/**
 * @brief Set the baud rate.
 *
 * The divider is 100 MHz / BaudRate rounded to the nearest integer, and must
 * be between 8 and 65535 (about 1526 baud to 12.5 Mbaud). Call while the link
 * is idle; the ESP32 must use the same rate.
 *
 * @return XST_SUCCESS or XST_INVALID_PARAM.
 */
int MBWB_ESP_setBaudRate(u32 BaudRate);

/** @brief Get the actual baud rate (100 MHz / divider). */
u32 MBWB_ESP_getBaudRate(void);

/**
 * @brief Enable or disable RTS/CTS hardware flow control.
 *
 * With flow control on, the FPGA only transmits while the ESP32 holds its
 * RTS (our ESP_CTS_N) low, and deasserts our RTS when the RX FIFO is nearly
 * full. Enable it only if the ESP32 firmware also enables hardware flow
 * control; otherwise transmission waits forever.
 */
void MBWB_ESP_enableFlowControl(bool Enable);

/**
 * @brief Enable or disable internal loopback (TX connected to RX).
 *
 * For self-test without an ESP32. ESP_TXD idles high while loopback is on.
 */
void MBWB_ESP_setLoopback(bool Enable);

/** @brief Read the raw ESP_STATUS register (MBWB_ESP_STATUS_* masks). */
u32 MBWB_ESP_getStatus(void);

/** @brief Get the sticky error flags (MBWB_ESP_ERR_* masks). */
u32 MBWB_ESP_getErrors(void);

/** @brief Clear the error flags given in @p Mask (MBWB_ESP_ERR_ALL for all). */
void MBWB_ESP_clearErrors(u32 Mask);

/** @brief Get the hardware RX / TX FIFO depths in bytes. */
u32 MBWB_ESP_getRxFifoSize(void);
u32 MBWB_ESP_getTxFifoSize(void);

/* -------------------------------------------------------------------------- */
/*  Transmit                                                                  */
/* -------------------------------------------------------------------------- */

/** @brief Number of bytes that can be queued without waiting. */
u32 MBWB_ESP_txFree(void);

/** @brief True when the TX FIFO is empty and the last byte has been sent. */
bool MBWB_ESP_isTxIdle(void);

/** @brief Wait until every queued byte has been sent. */
void MBWB_ESP_waitTxIdle(void);

/** @brief Queue one byte, waiting for space if necessary. */
void MBWB_ESP_writeByte(u8 Byte);

/**
 * @brief Queue @p Length bytes, waiting for space as needed.
 *
 * Returns once all bytes are in the TX FIFO (not necessarily sent).
 */
void MBWB_ESP_write(const u8 *Data, u32 Length);

/** @brief Queue a NUL-terminated string (the NUL is not sent). */
void MBWB_ESP_writeString(const char *String);

/**
 * @brief Queue as many bytes as fit right now, without waiting.
 *
 * @return Number of bytes queued (0 .. Length).
 */
u32 MBWB_ESP_tryWrite(const u8 *Data, u32 Length);

/** @brief Discard everything in the TX FIFO that has not started sending. */
void MBWB_ESP_flushTx(void);

/* -------------------------------------------------------------------------- */
/*  Receive                                                                   */
/* -------------------------------------------------------------------------- */

/** @brief Number of received bytes ready to read. */
u32 MBWB_ESP_rxAvailable(void);

/**
 * @brief Read up to @p MaxLength received bytes without waiting.
 *
 * @return Number of bytes copied to @p Buffer (0 if none are available).
 */
u32 MBWB_ESP_read(u8 *Buffer, u32 MaxLength);

/**
 * @brief Read one byte without waiting.
 *
 * @return The byte (0..255), or -1 if none is available.
 */
int MBWB_ESP_readByte(void);

/**
 * @brief Wait up to @p TimeoutUs microseconds for one byte.
 *
 * @return true and the byte in @p Byte, or false on timeout. A timeout of 0
 *         waits forever.
 */
bool MBWB_ESP_readByteTimeout(u8 *Byte, u32 TimeoutUs);

/** @brief Discard all received data (hardware FIFO and software ring). */
void MBWB_ESP_flushRx(void);

/* -------------------------------------------------------------------------- */
/*  Interrupt-driven receive                                                  */
/* -------------------------------------------------------------------------- */

/**
 * @brief Set when the RX interrupt fires.
 *
 * @param Threshold   Interrupt when this many bytes are waiting (1..FIFO size).
 * @param TimeoutBits Also interrupt when fewer bytes are waiting but the line
 *                    has been idle this many bit times (0 = never). This is
 *                    what delivers the end of a short message.
 */
void MBWB_ESP_setRxInterruptConfig(u32 Threshold, u32 TimeoutBits);

/**
 * @brief Switch between polled and interrupt-driven receive.
 *
 * Connect MBWB_ESP_interruptHandler() to the interrupt controller before
 * enabling. Bytes already in the hardware FIFO are delivered through the
 * interrupt once enabled.
 */
void MBWB_ESP_enableRxInterrupt(bool Enable);

/**
 * @brief Register a callback run from the interrupt handler after it has
 *        moved received bytes into the ring (e.g. to give a semaphore).
 *        Pass NULL to remove it.
 */
void MBWB_ESP_setRxCallback(MBWB_ESP_RxCallback Callback, void *CallbackRef);

/**
 * @brief Interrupt handler for MBWB_ESP_INTERRUPT_ID.
 *
 * @param CallbackRef Unused (pass NULL when connecting).
 */
void MBWB_ESP_interruptHandler(void *CallbackRef);

/** @brief Number of times the interrupt handler has run (for diagnostics). */
u32 MBWB_ESP_getInterruptCount(void);

#ifdef __cplusplus
}
#endif

#endif /* MBWB_ESP_H */
