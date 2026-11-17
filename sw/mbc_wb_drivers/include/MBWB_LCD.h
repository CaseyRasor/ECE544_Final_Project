/**
 * @file    MBWB_LCD.h
 * @brief   Public API for the MBWB ST7796S SPI TFT LCD driver.
 *
 * @date    16-Nov-2026
 * @version 1.0
 *
 * @detail
 * This driver controls a 320 x 480 ST7796S TFT panel through the wb_lcd
 * Wishbone peripheral (Wishbone region 3, which replaces the VGA text
 * controller in the MBC_WB platform).
 *
 * The hardware is a command/data FIFO feeding an SPI shift engine. The driver
 * builds everything else in software:
 *
 *   - Panel reset and ST7796S initialization sequence
 *   - Rotation (portrait/landscape), color inversion, backlight, sleep
 *   - Address windowing (CASET/RASET/RAMWR)
 *   - Graphics: pixels, lines, rectangles, filled rectangles, images
 *     (solid fills use the hardware FILL repeat, so a full-screen clear is
 *     a single bus write)
 *   - Text: CP437 8x16 font (same font as the VGA controller), scalable,
 *     with a VGA-style character console (cursor, putChar, putString, printf)
 *
 * Colors are 16-bit RGB565 values:
 *
 *   - Bits [15:11] : Red   (5 bits)
 *   - Bits [10:5]  : Green (6 bits)
 *   - Bits [4:0]   : Blue  (5 bits)
 *
 * Coordinates are in pixels with (0,0) at the top-left corner of the current
 * rotation. Drawing functions clip to the screen.
 *
 * Calls are not thread-safe. Under FreeRTOS, use the LCD from a single task
 * or protect it with a mutex.
 *
 * Build-time options (define before including, or with -D compiler flags):
 *
 *   - MBWB_LCD_COLOR_ORDER_BGR (default 1): set to 0 if red and blue are
 *     swapped on your panel.
 *   - MBWB_LCD_INVERT_COLORS (default 0): set to 1 if colors appear inverted
 *     (black shows as white); some ST7796S modules need display inversion on.
 *   - MBWB_LCD_DEFAULT_CLKDIV (default 3 = 12.5 MHz SCLK).
 *   - MBWB_LCD_DELAY_MS(ms): delay used during initialization (default
 *     usleep() from sleep.h).
 */
/* SPDX-License-Identifier: MIT */

#ifndef MBWB_LCD_H
#define MBWB_LCD_H

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

#ifndef MBWB_LCD_COLOR_ORDER_BGR
#define MBWB_LCD_COLOR_ORDER_BGR      1
#endif

#ifndef MBWB_LCD_INVERT_COLORS
#define MBWB_LCD_INVERT_COLORS        0
#endif

/**
 * @brief Default SPI clock divider.
 *
 * SCLK = 100 MHz / (2 * (ClockDivider + 1)):
 *   0 -> 50 MHz, 1 -> 25 MHz, 2 -> 16.7 MHz, 3 -> 12.5 MHz, 4 -> 10 MHz.
 * The ST7796S datasheet minimum write cycle is 66 ns (~15 MHz), but most
 * modules run reliably at 25 MHz or faster with short wiring.
 */
#ifndef MBWB_LCD_DEFAULT_CLKDIV
#define MBWB_LCD_DEFAULT_CLKDIV       3U
#endif

/* -------------------------------------------------------------------------- */
/*  Panel geometry                                                            */
/* -------------------------------------------------------------------------- */

/** @brief Native (portrait) panel width in pixels. */
#define MBWB_LCD_NATIVE_WIDTH         320U

/** @brief Native (portrait) panel height in pixels. */
#define MBWB_LCD_NATIVE_HEIGHT        480U

/** @brief Font glyph width in pixels (before scaling). */
#define MBWB_LCD_FONT_WIDTH           8U

/** @brief Font glyph height in pixels (before scaling). */
#define MBWB_LCD_FONT_HEIGHT          16U

/* -------------------------------------------------------------------------- */
/*  Rotation                                                                  */
/* -------------------------------------------------------------------------- */

#define MBWB_LCD_ROTATION_PORTRAIT            0U  /* 320 x 480 */
#define MBWB_LCD_ROTATION_LANDSCAPE           1U  /* 480 x 320 */
#define MBWB_LCD_ROTATION_PORTRAIT_FLIPPED    2U  /* 320 x 480 */
#define MBWB_LCD_ROTATION_LANDSCAPE_FLIPPED   3U  /* 480 x 320 */

/* -------------------------------------------------------------------------- */
/*  Colors (RGB565)                                                           */
/* -------------------------------------------------------------------------- */

/**
 * @brief Build an RGB565 color from 8-bit red, green, and blue components.
 */
#define MBWB_LCD_RGB565(Red, Green, Blue)                                    \
    ((u16)((((u16)(Red)   & 0xF8U) << 8U) |                                 \
           (((u16)(Green) & 0xFCU) << 3U) |                                 \
           (((u16)(Blue)  & 0xF8U) >> 3U)))

/**
 * @brief Convert a 12-bit VGA 0xRGB color to RGB565.
 *
 * Useful when porting code written for the MBWB VGA driver.
 */
#define MBWB_LCD_RGB444_TO_565(Rgb444)                                       \
    MBWB_LCD_RGB565((((Rgb444) >> 8U) & 0xFU) * 17U,                         \
                    (((Rgb444) >> 4U) & 0xFU) * 17U,                         \
                    ((Rgb444) & 0xFU) * 17U)

#define MBWB_LCD_BLACK                0x0000U
#define MBWB_LCD_WHITE                0xFFFFU
#define MBWB_LCD_RED                  0xF800U
#define MBWB_LCD_GREEN                0x07E0U
#define MBWB_LCD_BLUE                 0x001FU
#define MBWB_LCD_YELLOW               0xFFE0U
#define MBWB_LCD_CYAN                 0x07FFU
#define MBWB_LCD_MAGENTA              0xF81FU
#define MBWB_LCD_ORANGE               0xFD20U
#define MBWB_LCD_GRAY                 0x8410U
#define MBWB_LCD_DARKGRAY             0x4208U
#define MBWB_LCD_NAVY                 0x000FU
#define MBWB_LCD_DARKGREEN            0x03E0U

/* -------------------------------------------------------------------------- */
/*  ST7796S command codes (subset)                                            */
/* -------------------------------------------------------------------------- */

#define ST7796_NOP        0x00U
#define ST7796_SWRESET    0x01U
#define ST7796_SLPIN      0x10U
#define ST7796_SLPOUT     0x11U
#define ST7796_NORON      0x13U
#define ST7796_INVOFF     0x20U
#define ST7796_INVON      0x21U
#define ST7796_DISPOFF    0x28U
#define ST7796_DISPON     0x29U
#define ST7796_CASET      0x2AU
#define ST7796_RASET      0x2BU
#define ST7796_RAMWR      0x2CU
#define ST7796_VSCRDEF    0x33U
#define ST7796_MADCTL     0x36U
#define ST7796_VSCRSADD   0x37U
#define ST7796_COLMOD     0x3AU
#define ST7796_FRMCTR1    0xB1U
#define ST7796_DIC        0xB4U
#define ST7796_DFC        0xB6U
#define ST7796_EM         0xB7U
#define ST7796_PWR1       0xC0U
#define ST7796_PWR2       0xC1U
#define ST7796_PWR3       0xC2U
#define ST7796_VCMPCTL    0xC5U
#define ST7796_PGC        0xE0U
#define ST7796_NGC        0xE1U
#define ST7796_DOCA       0xE8U
#define ST7796_CSCON      0xF0U

#define ST7796_MADCTL_MY  0x80U
#define ST7796_MADCTL_MX  0x40U
#define ST7796_MADCTL_MV  0x20U
#define ST7796_MADCTL_ML  0x10U
#define ST7796_MADCTL_BGR 0x08U

/* -------------------------------------------------------------------------- */
/*  Initialization and panel control                                          */
/* -------------------------------------------------------------------------- */

/**
 * @brief Initialize the LCD peripheral and the ST7796S panel.
 *
 * Verifies the peripheral ID register, sets the default SPI clock, pulses the
 * panel reset, sends the ST7796S initialization sequence, selects portrait
 * rotation, clears the screen to black, and turns on the display and
 * backlight. Blocks for roughly 0.5 s while the panel powers up.
 *
 * @param BaseAddress Base address of the LCD peripheral. For the standard
 *                    MBWB platform, use MBWB_LCD_BASEADDR.
 *
 * @return XST_SUCCESS on success; XST_DEVICE_NOT_FOUND if the ID register
 *         does not match (wrong bitstream or base address).
 */
int MBWB_LCD_initialize(UINTPTR BaseAddress);

/**
 * @brief Set the SPI clock divider. SCLK = 100 MHz / (2 * (ClockDivider + 1)).
 *
 * Waits for any transfer in progress to complete before changing the clock.
 */
void MBWB_LCD_setClockDivider(u8 ClockDivider);

/** @brief Turn the backlight on or off. */
void MBWB_LCD_setBacklight(bool On);

/** @brief Turn the display output on (DISPON) or off (DISPOFF). */
void MBWB_LCD_displayOn(bool On);

/** @brief Turn display color inversion on (INVON) or off (INVOFF). */
void MBWB_LCD_setInversion(bool Invert);

/**
 * @brief Enter (true) or leave (false) panel sleep mode.
 *
 * Leaving sleep mode waits 120 ms as required by the ST7796S.
 */
void MBWB_LCD_sleep(bool Enter);

/**
 * @brief Select the screen rotation (MBWB_LCD_ROTATION_xxx).
 *
 * Updates the width/height reported by MBWB_LCD_getWidth() and
 * MBWB_LCD_getHeight() and resets the text cursor. Existing screen contents
 * are not redrawn.
 */
void MBWB_LCD_setRotation(u32 Rotation);

/** @brief Current rotation (MBWB_LCD_ROTATION_xxx). */
u32 MBWB_LCD_getRotation(void);

/** @brief Screen width in pixels for the current rotation. */
u32 MBWB_LCD_getWidth(void);

/** @brief Screen height in pixels for the current rotation. */
u32 MBWB_LCD_getHeight(void);

/* -------------------------------------------------------------------------- */
/*  Interface status and interrupt                                            */
/* -------------------------------------------------------------------------- */

/**
 * @brief Return true while the FIFO holds data or a transfer is in progress.
 */
bool MBWB_LCD_isBusy(void);

/**
 * @brief Busy-wait until every queued command and pixel has been sent.
 *
 * Drawing functions return as soon as their data is queued; call this before
 * timing-critical operations or before reconfiguring the panel.
 */
void MBWB_LCD_waitIdle(void);

/**
 * @brief Discard everything queued in the FIFO and abort the current transfer.
 *
 * The panel may be left in the middle of a RAMWR; issue a new window before
 * drawing again (all drawing functions do this).
 */
void MBWB_LCD_flush(void);

/**
 * @brief Enable or disable the "interface idle" interrupt.
 *
 * When enabled the peripheral asserts its IRQ (interrupt-controller input
 * MBWB_LCD_INTERRUPT_ID) whenever the FIFO is empty and no transfer is in
 * progress. The IRQ is a level: if the interrupt controller input is
 * level-sensitive the ISR must call MBWB_LCD_enableIdleInterrupt(false)
 * (or queue more data) before returning, otherwise it will re-enter
 * immediately.
 */
void MBWB_LCD_enableIdleInterrupt(bool Enable);

/* -------------------------------------------------------------------------- */
/*  Low-level panel access                                                    */
/* -------------------------------------------------------------------------- */

/** @brief Queue one command byte (DC = 0). */
void MBWB_LCD_writeCommand(u8 Command);

/** @brief Queue one data byte (DC = 1). */
void MBWB_LCD_writeData(u8 Data);

/**
 * @brief Queue a command followed by its parameter bytes.
 *
 * @param Command  ST7796S command code.
 * @param Data     Pointer to the parameter bytes (may be NULL if Length is 0).
 * @param Length   Number of parameter bytes.
 */
void MBWB_LCD_writeCommandData(u8 Command, const u8 *Data, u32 Length);

/**
 * @brief Set the drawing window and start a memory write (CASET/RASET/RAMWR).
 *
 * After this call, pixels written with MBWB_LCD_writePixels() or
 * MBWB_LCD_writeColor() fill the window left-to-right, top-to-bottom.
 * Coordinates are inclusive and are NOT clipped.
 */
void MBWB_LCD_setWindow(u32 X0, u32 Y0, u32 X1, u32 Y1);

/** @brief Queue Count pixels from a buffer into the current window. */
void MBWB_LCD_writePixels(const u16 *Pixels, u32 Count);

/** @brief Queue Count copies of one color into the current window (hardware fill). */
void MBWB_LCD_writeColor(u16 Color, u32 Count);

/* -------------------------------------------------------------------------- */
/*  Graphics                                                                  */
/* -------------------------------------------------------------------------- */

/** @brief Fill the whole screen with one color. */
void MBWB_LCD_fillScreen(u16 Color);

/** @brief Draw a single pixel. */
void MBWB_LCD_drawPixel(s32 X, s32 Y, u16 Color);

/** @brief Draw a horizontal line of Width pixels starting at (X, Y). */
void MBWB_LCD_drawHLine(s32 X, s32 Y, s32 Width, u16 Color);

/** @brief Draw a vertical line of Height pixels starting at (X, Y). */
void MBWB_LCD_drawVLine(s32 X, s32 Y, s32 Height, u16 Color);

/** @brief Draw a line between two points (Bresenham). */
void MBWB_LCD_drawLine(s32 X0, s32 Y0, s32 X1, s32 Y1, u16 Color);

/** @brief Draw a rectangle outline. */
void MBWB_LCD_drawRect(s32 X, s32 Y, s32 Width, s32 Height, u16 Color);

/** @brief Draw a filled rectangle. */
void MBWB_LCD_fillRect(s32 X, s32 Y, s32 Width, s32 Height, u16 Color);

/** @brief Draw a circle outline centered at (X0, Y0). */
void MBWB_LCD_drawCircle(s32 X0, s32 Y0, s32 Radius, u16 Color);

/** @brief Draw a filled circle centered at (X0, Y0). */
void MBWB_LCD_fillCircle(s32 X0, s32 Y0, s32 Radius, u16 Color);

/**
 * @brief Draw an RGB565 image stored row-major (Width * Height pixels).
 *
 * Images that extend past the screen edge are clipped.
 */
void MBWB_LCD_drawImage(s32 X, s32 Y, u32 Width, u32 Height,
                        const u16 *Pixels);

/* -------------------------------------------------------------------------- */
/*  Text drawing at pixel coordinates                                         */
/* -------------------------------------------------------------------------- */

/**
 * @brief Draw one CP437 character with its top-left corner at (X, Y).
 *
 * The character cell is (8 * Scale) x (16 * Scale) pixels and is drawn
 * opaque (background pixels are painted with Background).
 */
void MBWB_LCD_drawChar(s32 X, s32 Y, char Character,
                       u16 Foreground, u16 Background, u32 Scale);

/**
 * @brief Draw a string with its top-left corner at (X, Y).
 *
 * No wrapping or control-character processing is performed.
 */
void MBWB_LCD_drawString(s32 X, s32 Y, const char *String,
                         u16 Foreground, u16 Background, u32 Scale);

/* -------------------------------------------------------------------------- */
/*  Text console (VGA-driver-style API)                                       */
/* -------------------------------------------------------------------------- */

/**
 * @brief Set the console text colors.
 */
void MBWB_LCD_setTextColors(u16 Foreground, u16 Background);

/**
 * @brief Set the console text scale (1 = 8x16 cells, 2 = 16x32, ...).
 *
 * Changing the scale changes the number of rows/columns and homes the cursor.
 */
void MBWB_LCD_setTextScale(u32 Scale);

/** @brief Number of console text columns for the current rotation/scale. */
u32 MBWB_LCD_getTextCols(void);

/** @brief Number of console text rows for the current rotation/scale. */
u32 MBWB_LCD_getTextRows(void);

/** @brief Clear the screen to the console background color and home the cursor. */
void MBWB_LCD_clear(void);

/** @brief Set the console cursor (character row and column). */
void MBWB_LCD_setCursor(u32 Row, u32 Col);

/** @brief Get the console cursor (either pointer may be NULL). */
void MBWB_LCD_getCursor(u32 *Row, u32 *Col);

/** @brief Move the console cursor to row 0, column 0. */
void MBWB_LCD_home(void);

/**
 * @brief Write one character at the console cursor and advance it.
 *
 *   - '\n' moves to column 0 of the next row
 *   - '\r' moves to column 0 of the current row
 *
 * The cursor wraps at the right edge and from the bottom row back to the top.
 * When the cursor moves onto a new row, that row is cleared first so that
 * old text does not mix with new text.
 */
void MBWB_LCD_putChar(char Character);

/** @brief Write a null-terminated string at the console cursor. */
void MBWB_LCD_putString(const char *String);

/**
 * @brief Formatted console output.
 *
 * Supports %c %s %d %i %u %x %X %p %% with optional zero padding and field
 * width (same subset as MBWB_VGA_printf()). No floating point.
 */
void MBWB_LCD_printf(const char *Format, ...);

/* -------------------------------------------------------------------------- */
/*  Font data                                                                 */
/* -------------------------------------------------------------------------- */

/**
 * @brief CP437 8x16 font: byte [Character * 16 + Row], bit 7 = leftmost pixel.
 *
 * Defined in MBWB_LCD_font.c.
 */
extern const u8 MBWB_LCD_Font8x16[256U * 16U];

#ifdef __cplusplus
}
#endif

#endif /* MBWB_LCD_H */
