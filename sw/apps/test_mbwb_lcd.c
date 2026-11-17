/**
 * @file    test_mbwb_lcd.c
 * @brief   Functional test for the MBWB ST7796S SPI LCD driver.
 *
 * @date    16-Nov-2026
 * @version 1.0
 *
 * @detail
 * Exercises the MBWB LCD driver: initialization, color fills, graphics
 * primitives, image drawing, scaled text, the text console with printf, and
 * all four rotations. Progress is reported on the UART.
 *
 * If the colors look wrong:
 *   - red and blue swapped  -> rebuild with -DMBWB_LCD_COLOR_ORDER_BGR=0
 *   - black looks white     -> rebuild with -DMBWB_LCD_INVERT_COLORS=1
 * (or call MBWB_LCD_setInversion() at run time).
 */
/* SPDX-License-Identifier: MIT */

#include "MBWB_LCD.h"

#include "sleep.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "xstatus.h"

/* -------------------------------------------------------------------------- */
/*  Test configuration                                                        */
/* -------------------------------------------------------------------------- */

#define TEST_LCD_STEP_DELAY_S      2U
#define TEST_LCD_FAST_CLKDIV       1U      /* 25 MHz SCLK after init */

/* -------------------------------------------------------------------------- */
/*  Private helper-function prototypes                                        */
/* -------------------------------------------------------------------------- */

static void TEST_LCD_pause(const char *Message);
static void TEST_LCD_colorBars(void);
static void TEST_LCD_graphics(void);
static void TEST_LCD_image(void);
static void TEST_LCD_text(void);
static void TEST_LCD_console(void);
static void TEST_LCD_rotations(void);

/* -------------------------------------------------------------------------- */
/*  Main application                                                          */
/* -------------------------------------------------------------------------- */

int main(void)
{
    int Status;

    xil_printf("\r\n");
    xil_printf("MBWB ST7796S LCD driver functional test\r\n");
    xil_printf("--------------------------------------------------\r\n");
    xil_printf("Initializing the LCD driver at 0x%08lx...\r\n",
               (unsigned long)MBWB_LCD_BASEADDR);

    Status = MBWB_LCD_initialize(MBWB_LCD_BASEADDR);

    if (Status != XST_SUCCESS)
    {
        xil_printf("ERROR: LCD peripheral not found (ID register mismatch)\r\n");
        return XST_FAILURE;
    }

    xil_printf("LCD initialized: %u x %u\r\n",
               (unsigned)MBWB_LCD_getWidth(), (unsigned)MBWB_LCD_getHeight());

    MBWB_LCD_setClockDivider(TEST_LCD_FAST_CLKDIV);

    TEST_LCD_colorBars();
    TEST_LCD_graphics();
    TEST_LCD_image();
    TEST_LCD_text();
    TEST_LCD_console();
    TEST_LCD_rotations();

    xil_printf("LCD test complete.\r\n");

    MBWB_LCD_setRotation(MBWB_LCD_ROTATION_PORTRAIT);
    MBWB_LCD_setTextColors(MBWB_LCD_GREEN, MBWB_LCD_BLACK);
    MBWB_LCD_setTextScale(2U);
    MBWB_LCD_clear();
    MBWB_LCD_putString("LCD TEST\nCOMPLETE");

    return XST_SUCCESS;
}

/* -------------------------------------------------------------------------- */
/*  Test steps                                                                */
/* -------------------------------------------------------------------------- */

static void TEST_LCD_pause(const char *Message)
{
    xil_printf("  %s\r\n", Message);
    MBWB_LCD_waitIdle();
    sleep(TEST_LCD_STEP_DELAY_S);
}

/***** Full-screen fills and vertical color bars *****/
static void TEST_LCD_colorBars(void)
{
    static const u16 Colors[] =
    {
        MBWB_LCD_RED, MBWB_LCD_GREEN, MBWB_LCD_BLUE, MBWB_LCD_WHITE,
        MBWB_LCD_BLACK
    };
    static const char *Names[] = { "red", "green", "blue", "white", "black" };
    static const u16 Bars[8] =
    {
        MBWB_LCD_WHITE, MBWB_LCD_YELLOW, MBWB_LCD_CYAN, MBWB_LCD_GREEN,
        MBWB_LCD_MAGENTA, MBWB_LCD_RED, MBWB_LCD_BLUE, MBWB_LCD_BLACK
    };
    const s32 W = (s32)MBWB_LCD_getWidth();
    const s32 H = (s32)MBWB_LCD_getHeight();
    u32 Index;

    xil_printf("Test 1: full-screen fills (check red/green/blue order)\r\n");

    for (Index = 0U; Index < (sizeof(Colors) / sizeof(Colors[0])); Index++)
    {
        MBWB_LCD_fillScreen(Colors[Index]);
        TEST_LCD_pause(Names[Index]);
    }

    for (Index = 0U; Index < 8U; Index++)
    {
        MBWB_LCD_fillRect((s32)Index * W / 8, 0, W / 8 + 1, H, Bars[Index]);
    }

    TEST_LCD_pause("color bars: white yellow cyan green magenta red blue black");
}

/***** Lines, rectangles, circles *****/
static void TEST_LCD_graphics(void)
{
    const s32 W = (s32)MBWB_LCD_getWidth();
    const s32 H = (s32)MBWB_LCD_getHeight();
    s32 I;

    xil_printf("Test 2: graphics primitives\r\n");

    MBWB_LCD_fillScreen(MBWB_LCD_BLACK);
    MBWB_LCD_drawRect(0, 0, W, H, MBWB_LCD_WHITE);           /* screen border */

    for (I = 0; I < W; I += 20)                               /* line fan */
    {
        MBWB_LCD_drawLine(0, H - 1, I, H / 2, MBWB_LCD_CYAN);
    }

    MBWB_LCD_fillRect(20, 20, 100, 60, MBWB_LCD_RED);
    MBWB_LCD_drawRect(130, 20, 100, 60, MBWB_LCD_YELLOW);
    MBWB_LCD_fillCircle(W / 2, H / 3, 50, MBWB_LCD_BLUE);
    MBWB_LCD_drawCircle(W / 2, H / 3, 60, MBWB_LCD_GREEN);
    MBWB_LCD_drawLine(0, 0, W - 1, H - 1, MBWB_LCD_MAGENTA);
    MBWB_LCD_drawLine(W - 1, 0, 0, H - 1, MBWB_LCD_MAGENTA);

    /* Clipping: shapes hanging off every edge. */
    MBWB_LCD_fillCircle(0, 0, 30, MBWB_LCD_ORANGE);
    MBWB_LCD_fillRect(W - 20, H - 20, 60, 60, MBWB_LCD_ORANGE);

    TEST_LCD_pause("border, line fan, rectangles, circles, diagonals, clipped corners");
}

/***** RGB565 image (generated gradient) *****/
static void TEST_LCD_image(void)
{
    static u16 Image[64U * 64U];
    u32 X, Y;

    xil_printf("Test 3: image blit\r\n");

    for (Y = 0U; Y < 64U; Y++)
    {
        for (X = 0U; X < 64U; X++)
        {
            Image[(Y * 64U) + X] = MBWB_LCD_RGB565(X * 4U, Y * 4U, 255U - (X * 4U));
        }
    }

    MBWB_LCD_fillScreen(MBWB_LCD_DARKGRAY);

    for (Y = 0U; Y < 4U; Y++)
    {
        for (X = 0U; X < 4U; X++)
        {
            MBWB_LCD_drawImage((s32)(X * 80U) + 8, (s32)(Y * 80U) + 8,
                               64U, 64U, Image);
        }
    }

    MBWB_LCD_drawImage(-32, (s32)MBWB_LCD_getHeight() - 32, 64U, 64U, Image);

    TEST_LCD_pause("4x4 gradient tiles + one clipped at bottom-left");
}

/***** Text at pixel positions, several scales and colors *****/
static void TEST_LCD_text(void)
{
    u32 Ch;

    xil_printf("Test 4: text drawing\r\n");

    MBWB_LCD_fillScreen(MBWB_LCD_NAVY);
    MBWB_LCD_drawString(4, 4, "Scale 1: Hello, ST7796S!",
                        MBWB_LCD_WHITE, MBWB_LCD_NAVY, 1U);
    MBWB_LCD_drawString(4, 24, "Scale 2",
                        MBWB_LCD_YELLOW, MBWB_LCD_NAVY, 2U);
    MBWB_LCD_drawString(4, 60, "x3",
                        MBWB_LCD_BLACK, MBWB_LCD_ORANGE, 3U);

    /* Full CP437 character set, 32 per row. */
    for (Ch = 0U; Ch < 256U; Ch++)
    {
        MBWB_LCD_drawChar((s32)((Ch % 32U) * 10U), (s32)(120U + (Ch / 32U) * 18U),
                          (char)Ch, MBWB_LCD_GREEN, MBWB_LCD_BLACK, 1U);
    }

    TEST_LCD_pause("strings at scales 1-3 and the CP437 character set");
}

/***** VGA-style console *****/
static void TEST_LCD_console(void)
{
    u32 Line;

    xil_printf("Test 5: text console (%u cols x %u rows)\r\n",
               (unsigned)MBWB_LCD_getTextCols(), (unsigned)MBWB_LCD_getTextRows());

    MBWB_LCD_setTextColors(MBWB_LCD_WHITE, MBWB_LCD_BLACK);
    MBWB_LCD_setTextScale(1U);
    MBWB_LCD_clear();

    MBWB_LCD_printf("MBWB LCD console %ux%u\n",
                    (unsigned)MBWB_LCD_getTextCols(),
                    (unsigned)MBWB_LCD_getTextRows());
    MBWB_LCD_printf("dec %d  neg %d  hex 0x%08X  str [%8s]\n",
                    12345, -42, 0xBEEFU, "pad");
    MBWB_LCD_setTextColors(MBWB_LCD_YELLOW, MBWB_LCD_BLACK);
    MBWB_LCD_putString("This line is long enough that it wraps around the right "
                       "edge of the screen onto the next row.\n");
    MBWB_LCD_setTextColors(MBWB_LCD_WHITE, MBWB_LCD_BLACK);

    for (Line = 0U; Line < 40U; Line++)      /* wraps past the bottom */
    {
        MBWB_LCD_printf("line %02u\n", (unsigned)Line);
    }

    TEST_LCD_pause("printf formats, line wrap, bottom-to-top wrap");
}

/***** All four rotations *****/
static void TEST_LCD_rotations(void)
{
    u32 Rotation;

    xil_printf("Test 6: rotations\r\n");

    for (Rotation = 0U; Rotation < 4U; Rotation++)
    {
        MBWB_LCD_setRotation(Rotation);
        MBWB_LCD_fillScreen(MBWB_LCD_BLACK);
        MBWB_LCD_drawRect(0, 0, (s32)MBWB_LCD_getWidth(),
                          (s32)MBWB_LCD_getHeight(), MBWB_LCD_RED);
        MBWB_LCD_fillRect(0, 0, 40, 40, MBWB_LCD_GREEN);   /* top-left marker */
        MBWB_LCD_drawString(50, 12, "TOP-LEFT", MBWB_LCD_WHITE, MBWB_LCD_BLACK, 1U);
        MBWB_LCD_setTextScale(2U);
        MBWB_LCD_setCursor(3U, 1U);
        MBWB_LCD_printf("Rotation %u\n %ux%u", (unsigned)Rotation,
                        (unsigned)MBWB_LCD_getWidth(),
                        (unsigned)MBWB_LCD_getHeight());
        MBWB_LCD_setTextScale(1U);

        TEST_LCD_pause("green square should be at the top-left of the text");
    }
}
