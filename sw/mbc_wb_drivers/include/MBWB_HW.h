/**
 * @file    MBWB_HW.h
 * @brief   Hardware definitions for the MBWB SoC driver library.
 *
 * @author Roy Kravitz (roy.kravitz@pdx.edu) and ChatGPT
 * @copyright Copyright (c) 2026 Roy Kravitz
 * @license MIT
 *
 * @date    16-Jul-2026
 * @version 1.0
 *
 * @detail
 * This header file defines the memory map for the MicroBlaze/Wishbone (MBWB)
 * embedded-system platform. It contains:
 *   - The AXI-Lite-to-Wishbone MMIO aperture
 *   - Wishbone peripheral base addresses
 *   - Common Wishbone register indices
 *   - Peripheral-specific MMIO register maps
 *   - Custom Wishbone interrupt-controller input assignments
 *
 * The Wishbone subsystem occupies a 256-Kbyte MMIO aperture beginning at the
 * base address exported by the AXI-Lite-to-Wishbone bridge. Address bits
 * [17:16] select one of four 64-Kbyte Wishbone peripheral regions:
 *   - Region 0: Board I/O
 *   - Region 1: Seven-segment display
 *   - Region 2: Error peripheral
 *   - Region 3: ST7796S SPI TFT LCD (replaces the VGA text display)
 * Each peripheral occupies one 64 KB MMIO region.
 *
 * All MBWB peripherals use 32-bit registers with:
 *
 *      register_address = peripheral_base + (register_index << 2)
 *
 */
/* SPDX-License-Identifier: MIT */

#ifndef MBWB_HW_H
#define MBWB_HW_H

#include "xparameters.h"
#include "xil_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------------- */
/*  AXI-Lite-to-Wishbone MMIO aperture                                        */
/* -------------------------------------------------------------------------- */

#define MBWB_MMIO_BASEADDR       XPAR_AXLITE2WBSP_0_BASEADDR
#define MBWB_MMIO_HIGHADDR       XPAR_AXLITE2WBSP_0_HIGHADDR
#define MBWB_MMIO_SIZE           0x00040000U

/* -------------------------------------------------------------------------- */
/*  Wishbone peripheral regions                                               */
/* -------------------------------------------------------------------------- */

#define MBWB_BIO_BASEADDR        (MBWB_MMIO_BASEADDR + 0x00000000U)
#define MBWB_SSEG_BASEADDR       (MBWB_MMIO_BASEADDR + 0x00010000U)
#define MBWB_ERR_BASEADDR        (MBWB_MMIO_BASEADDR + 0x00020000U)
#define MBWB_LCD_BASEADDR        (MBWB_MMIO_BASEADDR + 0x00030000U)

#define MBWB_PERIPHERAL_REGION_SIZE  0x00010000U

/* -------------------------------------------------------------------------- */
/*  Common Wishbone register indices                                          */
/* -------------------------------------------------------------------------- */

#define MBWB_REG0   0x00U
#define MBWB_REG1   0x01U
#define MBWB_REG2   0x02U
#define MBWB_REG3   0x03U
#define MBWB_REG4   0x04U
#define MBWB_REG5   0x05U
#define MBWB_REG6   0x06U
#define MBWB_REG7   0x07U
#define MBWB_REG8   0x08U
#define MBWB_REG9   0x09U
#define MBWB_REG10  0x0AU
#define MBWB_REG11  0x0BU
#define MBWB_REG12  0x0CU
#define MBWB_REG13  0x0DU
#define MBWB_REG14  0x0EU
#define MBWB_REG15  0x0FU
#define MBWB_REG16  0x10U

#define MBWB_REG_OFFSET(RegIndex)    ((u32)(RegIndex) << 2U)

/* -------------------------------------------------------------------------- */
/*  Board I/O peripheral register map                                         */
/* -------------------------------------------------------------------------- */

#define MBWB_BIO_BOARD_IN_REG         MBWB_REG0  // byte offset 0x00
#define MBWB_BIO_LEDS_REG             MBWB_REG1  // byte offset 0x04 
#define MBWB_BIO_IRQ_ENABLE_REG       MBWB_REG2  // byte offset 0x08 
#define MBWB_BIO_IRQ_STATUS_REG       MBWB_REG3  // byte offset 0x0C 
#define MBWB_BIO_BOARD_ID_REG         MBWB_REG4  // byte offset 0x10
#define MBWB_BIO_BOARD_CONFIG_REG     MBWB_REG5  // byte offset 0x14

#define MBWB_BIO_RGB_CONTROL_BASE_REG MBWB_REG8  // byte offset 0x20
#define MBWB_BIO_RGB_COUNT_BASE_REG   MBWB_REG16 // byte offset 0x40

#define MBWB_BIO_RGB_CONTROL_REG(Index) \
    (MBWB_BIO_RGB_CONTROL_BASE_REG + (u32)(Index))

#define MBWB_BIO_RGB_COUNT_REG(Index) \
    (MBWB_BIO_RGB_COUNT_BASE_REG + (u32)(Index))

/* RGB LED control-register fields. */
#define MBWB_BIO_RGB_ENABLE_MASK     0x80000000U
#define MBWB_BIO_RGB_RED_SHIFT       16U
#define MBWB_BIO_RGB_GREEN_SHIFT     8U
#define MBWB_BIO_RGB_BLUE_SHIFT      0U
#define MBWB_BIO_RGB_COMPONENT_MASK  0x000000FFU

/* -------------------------------------------------------------------------- */
/*  Seven-segment display peripheral register map                             */
/* -------------------------------------------------------------------------- */

#define MBWB_SSEG_ENABLES_REG        MBWB_REG0
#define MBWB_SSEG_DIGITS_LO_REG      MBWB_REG1
#define MBWB_SSEG_DIGITS_HI_REG      MBWB_REG2
#define MBWB_SSEG_RESERVED_REG       MBWB_REG3

/* -------------------------------------------------------------------------- */
/*  Error peripheral register map                                             */
/* -------------------------------------------------------------------------- */

#define MBWB_ERR_REG0                MBWB_REG0
#define MBWB_ERR_REG1                MBWB_REG1
#define MBWB_ERR_REG2                MBWB_REG2
#define MBWB_ERR_REG3                MBWB_REG3

/* -------------------------------------------------------------------------- */
/*  ST7796S SPI LCD peripheral register map (wb_lcd.sv)                       */
/* -------------------------------------------------------------------------- */

#define MBWB_LCD_CTRL_REG            MBWB_REG0  // byte offset 0x00  RW
#define MBWB_LCD_STATUS_REG          MBWB_REG1  // byte offset 0x04  RO
#define MBWB_LCD_CLKDIV_REG          MBWB_REG2  // byte offset 0x08  RW
#define MBWB_LCD_FILLCNT_REG         MBWB_REG3  // byte offset 0x0C  RW
#define MBWB_LCD_CMD_REG             MBWB_REG4  // byte offset 0x10  WO
#define MBWB_LCD_DATA8_REG           MBWB_REG5  // byte offset 0x14  WO
#define MBWB_LCD_DATA16_REG          MBWB_REG6  // byte offset 0x18  WO
#define MBWB_LCD_FILL_REG            MBWB_REG7  // byte offset 0x1C  WO
#define MBWB_LCD_ID_REG              MBWB_REG8  // byte offset 0x20  RO
#define MBWB_LCD_FIFOSZ_REG          MBWB_REG9  // byte offset 0x24  RO

/* LCD_CTRL fields */
#define MBWB_LCD_CTRL_RST_MASK       0x00000001U  // 1 = panel held in reset
#define MBWB_LCD_CTRL_BL_MASK        0x00000002U  // 1 = backlight on
#define MBWB_LCD_CTRL_IRQ_EN_MASK    0x00000004U  // 1 = IRQ while interface idle
#define MBWB_LCD_CTRL_FLUSH_MASK     0x00000008U  // write 1: empty FIFO, abort transfer

/* LCD_STATUS fields */
#define MBWB_LCD_STATUS_BUSY_MASK    0x00000001U
#define MBWB_LCD_STATUS_FULL_MASK    0x00000002U
#define MBWB_LCD_STATUS_EMPTY_MASK   0x00000004U
#define MBWB_LCD_STATUS_IRQ_MASK     0x00000008U
#define MBWB_LCD_STATUS_LEVEL_SHIFT  16U
#define MBWB_LCD_STATUS_LEVEL_MASK   0x03FF0000U

#define MBWB_LCD_CLKDIV_MASK         0x000000FFU
#define MBWB_LCD_FILLCNT_MASK        0x0003FFFFU
#define MBWB_LCD_ID_VALUE            0x37373936U  // "7796"

/* -------------------------------------------------------------------------- */
/*  AXI interrupt-controller input assignments                                */
/* -------------------------------------------------------------------------- */

/*
 * These interrupt IDs must match the bit positions of the interrupt sources
 * connected to the AXI Interrupt Controller in the Vivado block design.
 * Timer interrupt IDs are generated in xparameters.h. The Wishbone interrupt
 * inputs are external signals and therefore require MBWB-specific constants.
 */
#define MBWB_BIO_INTERRUPT_ID        2U
#define MBWB_LCD_INTERRUPT_ID        3U  // wb_irq1: LCD interface idle (level)
#define MBWB_RESERVED_INTERRUPT_ID   MBWB_LCD_INTERRUPT_ID  // legacy name

#ifdef __cplusplus
}
#endif

#endif /* MBWB_HW_H */
