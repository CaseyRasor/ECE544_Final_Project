/**
 * @file    MBWB_LCD.c
 * @brief   Implementation of the MBWB ST7796S SPI TFT LCD driver.
 *
 * @date    16-Nov-2026
 * @version 1.0
 *
 * @detail
 * See MBWB_LCD.h for the API description. All panel traffic goes through the
 * wb_lcd transmit FIFO:
 *
 *   - LCD_CMD    : command byte (DC = 0)
 *   - LCD_DATA8  : parameter byte (DC = 1)
 *   - LCD_DATA16 : one RGB565 pixel
 *   - LCD_FILL   : one RGB565 pixel repeated LCD_FILLCNT times
 *
 * If the FIFO is full, the hardware withholds the bus acknowledge until space
 * is available, so the driver never needs to poll before writing.
 */
/* SPDX-License-Identifier: MIT */

#include "MBWB_LCD.h"

#include <stdarg.h>
#include <stddef.h>

#ifndef MBWB_LCD_DELAY_MS
#include "sleep.h"
#define MBWB_LCD_DELAY_MS(Ms)   usleep((u32)(Ms) * 1000U)
#endif

/* -------------------------------------------------------------------------- */
/*  Private driver state                                                      */
/* -------------------------------------------------------------------------- */

/** @brief Base address of the LCD peripheral. */
static UINTPTR MBWB_LCD_BaseAddress = MBWB_LCD_BASEADDR;

/** @brief Shadow of the LCD_CTRL register (RST, BL, IRQ_EN bits only). */
static u32 MBWB_LCD_CtrlShadow = MBWB_LCD_CTRL_RST_MASK;

/** @brief Last value written to LCD_FILLCNT (avoids redundant bus writes). */
static u32 MBWB_LCD_FillCount = 1U;

/** @brief Current rotation and the resulting screen size. */
static u32 MBWB_LCD_Rotation = MBWB_LCD_ROTATION_PORTRAIT;
static s32 MBWB_LCD_Width    = (s32)MBWB_LCD_NATIVE_WIDTH;
static s32 MBWB_LCD_Height   = (s32)MBWB_LCD_NATIVE_HEIGHT;

/** @brief Console state. */
static u16 MBWB_LCD_TextFg     = MBWB_LCD_WHITE;
static u16 MBWB_LCD_TextBg     = MBWB_LCD_BLACK;
static u32 MBWB_LCD_TextScale  = 1U;
static u32 MBWB_LCD_CursorRow  = 0U;
static u32 MBWB_LCD_CursorCol  = 0U;

/* -------------------------------------------------------------------------- */
/*  ST7796S initialization sequence                                           */
/* -------------------------------------------------------------------------- */

typedef struct
{
    u8  Command;
    u8  Length;
    u8  Data[14];
    u16 DelayMs;
} MBWB_LCD_InitCmd;

/*
 * Standard ST7796S power-up sequence for 320 x 480 SPI modules, RGB565.
 * MADCTL, inversion, and DISPON are sent separately by MBWB_LCD_initialize().
 */
static const MBWB_LCD_InitCmd MBWB_LCD_InitSequence[] =
{
    { ST7796_SWRESET, 0U,  { 0 }, 120U },
    { ST7796_SLPOUT,  0U,  { 0 }, 120U },
    { ST7796_CSCON,   1U,  { 0xC3 }, 0U },              /* enable command 2 part I  */
    { ST7796_CSCON,   1U,  { 0x96 }, 0U },              /* enable command 2 part II */
    { ST7796_COLMOD,  1U,  { 0x55 }, 0U },              /* 16 bits/pixel */
    { ST7796_DIC,     1U,  { 0x01 }, 0U },              /* 1-dot inversion */
    { ST7796_DFC,     3U,  { 0x80, 0x02, 0x3B }, 0U },
    { ST7796_DOCA,    8U,  { 0x40, 0x8A, 0x00, 0x00, 0x29, 0x19, 0xA5, 0x33 }, 0U },
    { ST7796_PWR2,    1U,  { 0x06 }, 0U },
    { ST7796_PWR3,    1U,  { 0xA7 }, 0U },
    { ST7796_VCMPCTL, 1U,  { 0x18 }, 120U },
    { ST7796_PGC,     14U, { 0xF0, 0x09, 0x0B, 0x06, 0x04, 0x15, 0x2F,
                             0x54, 0x42, 0x3C, 0x17, 0x14, 0x18, 0x1B }, 0U },
    { ST7796_NGC,     14U, { 0xE0, 0x09, 0x0B, 0x06, 0x04, 0x03, 0x2B,
                             0x43, 0x42, 0x3B, 0x16, 0x14, 0x17, 0x1B }, 120U },
    { ST7796_CSCON,   1U,  { 0x3C }, 0U },              /* disable command 2 part I  */
    { ST7796_CSCON,   1U,  { 0x69 }, 120U },            /* disable command 2 part II */
    { ST7796_NORON,   0U,  { 0 }, 10U },
};

#define MBWB_LCD_INIT_SEQUENCE_LENGTH \
    (sizeof(MBWB_LCD_InitSequence) / sizeof(MBWB_LCD_InitSequence[0]))

/* MADCTL value for each rotation (before the color-order bit is added). */
static const u8 MBWB_LCD_MadctlRotation[4] =
{
    ST7796_MADCTL_MX,                                       /* portrait           */
    ST7796_MADCTL_MV,                                       /* landscape          */
    ST7796_MADCTL_MY,                                       /* portrait flipped   */
    ST7796_MADCTL_MX | ST7796_MADCTL_MY | ST7796_MADCTL_MV  /* landscape flipped  */
};

/* -------------------------------------------------------------------------- */
/*  Private helper-function prototypes                                        */
/* -------------------------------------------------------------------------- */

static void MBWB_LCD_writeCtrl(u32 Value);
static void MBWB_LCD_setFillCount(u32 Count);
static bool MBWB_LCD_clipRect(s32 *X, s32 *Y, s32 *Width, s32 *Height);
static void MBWB_LCD_newLine(void);
static void MBWB_LCD_clearTextRow(u32 Row);
static void MBWB_LCD_putUnsigned(u32 Value, u32 Base, bool Uppercase,
                                 u32 Width, char PadChar);
static void MBWB_LCD_putSigned(s32 Value, u32 Width, char PadChar);
static u32 MBWB_LCD_strlen(const char *String);

/* -------------------------------------------------------------------------- */
/*  Initialization and panel control                                          */
/* -------------------------------------------------------------------------- */

/***** MBWB_LCD_initialize() - Initialize the LCD peripheral and panel. *****/
int MBWB_LCD_initialize(UINTPTR BaseAddress)
{
    u32 Index;

    MBWB_LCD_BaseAddress = BaseAddress;

    if (MBWB_L_readReg(MBWB_LCD_BaseAddress, MBWB_LCD_ID_REG) !=
        MBWB_LCD_ID_VALUE)
    {
        return XST_DEVICE_NOT_FOUND;
    }

    /* Known interface state: FIFO empty, backlight off, IRQ off, panel in reset. */
    MBWB_LCD_CtrlShadow = MBWB_LCD_CTRL_RST_MASK;
    MBWB_LCD_writeCtrl(MBWB_LCD_CtrlShadow | MBWB_LCD_CTRL_FLUSH_MASK);

    MBWB_L_writeReg(MBWB_LCD_BaseAddress, MBWB_LCD_CLKDIV_REG,
                    MBWB_LCD_DEFAULT_CLKDIV & MBWB_LCD_CLKDIV_MASK);

    MBWB_LCD_FillCount = 1U;
    MBWB_L_writeReg(MBWB_LCD_BaseAddress, MBWB_LCD_FILLCNT_REG, 1U);

    /* Hardware reset pulse. */
    MBWB_LCD_DELAY_MS(10U);
    MBWB_LCD_CtrlShadow &= ~MBWB_LCD_CTRL_RST_MASK;
    MBWB_LCD_writeCtrl(MBWB_LCD_CtrlShadow);
    MBWB_LCD_DELAY_MS(120U);

    /* Controller initialization sequence. */
    for (Index = 0U; Index < MBWB_LCD_INIT_SEQUENCE_LENGTH; Index++)
    {
        const MBWB_LCD_InitCmd *Cmd = &MBWB_LCD_InitSequence[Index];

        MBWB_LCD_writeCommandData(Cmd->Command, Cmd->Data, Cmd->Length);

        if (Cmd->DelayMs != 0U)
        {
            MBWB_LCD_waitIdle();
            MBWB_LCD_DELAY_MS(Cmd->DelayMs);
        }
    }

    MBWB_LCD_setInversion(MBWB_LCD_INVERT_COLORS != 0);
    MBWB_LCD_setRotation(MBWB_LCD_ROTATION_PORTRAIT);

    MBWB_LCD_TextFg    = MBWB_LCD_WHITE;
    MBWB_LCD_TextBg    = MBWB_LCD_BLACK;
    MBWB_LCD_TextScale = 1U;

    /* Clear the frame memory before the display is turned on. */
    MBWB_LCD_fillScreen(MBWB_LCD_BLACK);
    MBWB_LCD_displayOn(true);
    MBWB_LCD_waitIdle();
    MBWB_LCD_DELAY_MS(20U);
    MBWB_LCD_setBacklight(true);

    return XST_SUCCESS;
}

/***** MBWB_LCD_setClockDivider() - Set the SPI clock divider. *****/
void MBWB_LCD_setClockDivider(u8 ClockDivider)
{
    MBWB_LCD_waitIdle();
    MBWB_L_writeReg(MBWB_LCD_BaseAddress, MBWB_LCD_CLKDIV_REG,
                    (u32)ClockDivider & MBWB_LCD_CLKDIV_MASK);
}

/***** MBWB_LCD_setBacklight() - Turn the backlight on or off. *****/
void MBWB_LCD_setBacklight(bool On)
{
    if (On)
    {
        MBWB_LCD_CtrlShadow |= MBWB_LCD_CTRL_BL_MASK;
    }
    else
    {
        MBWB_LCD_CtrlShadow &= ~MBWB_LCD_CTRL_BL_MASK;
    }

    MBWB_LCD_writeCtrl(MBWB_LCD_CtrlShadow);
}

/***** MBWB_LCD_displayOn() - Turn the display output on or off. *****/
void MBWB_LCD_displayOn(bool On)
{
    MBWB_LCD_writeCommand(On ? ST7796_DISPON : ST7796_DISPOFF);
}

/***** MBWB_LCD_setInversion() - Turn display inversion on or off. *****/
void MBWB_LCD_setInversion(bool Invert)
{
    MBWB_LCD_writeCommand(Invert ? ST7796_INVON : ST7796_INVOFF);
}

/***** MBWB_LCD_sleep() - Enter or leave panel sleep mode. *****/
void MBWB_LCD_sleep(bool Enter)
{
    MBWB_LCD_writeCommand(Enter ? ST7796_SLPIN : ST7796_SLPOUT);
    MBWB_LCD_waitIdle();
    MBWB_LCD_DELAY_MS(Enter ? 5U : 120U);
}

/***** MBWB_LCD_setRotation() - Select the screen rotation. *****/
void MBWB_LCD_setRotation(u32 Rotation)
{
    u8 Madctl;

    Rotation &= 0x3U;
    MBWB_LCD_Rotation = Rotation;

    Madctl = MBWB_LCD_MadctlRotation[Rotation];
#if MBWB_LCD_COLOR_ORDER_BGR
    Madctl |= ST7796_MADCTL_BGR;
#endif

    MBWB_LCD_writeCommandData(ST7796_MADCTL, &Madctl, 1U);

    if ((Rotation & 0x1U) != 0U)
    {
        MBWB_LCD_Width  = (s32)MBWB_LCD_NATIVE_HEIGHT;
        MBWB_LCD_Height = (s32)MBWB_LCD_NATIVE_WIDTH;
    }
    else
    {
        MBWB_LCD_Width  = (s32)MBWB_LCD_NATIVE_WIDTH;
        MBWB_LCD_Height = (s32)MBWB_LCD_NATIVE_HEIGHT;
    }

    MBWB_LCD_home();
}

/***** MBWB_LCD_getRotation() - Current rotation. *****/
u32 MBWB_LCD_getRotation(void)
{
    return MBWB_LCD_Rotation;
}

/***** MBWB_LCD_getWidth() - Screen width for the current rotation. *****/
u32 MBWB_LCD_getWidth(void)
{
    return (u32)MBWB_LCD_Width;
}

/***** MBWB_LCD_getHeight() - Screen height for the current rotation. *****/
u32 MBWB_LCD_getHeight(void)
{
    return (u32)MBWB_LCD_Height;
}

/* -------------------------------------------------------------------------- */
/*  Interface status and interrupt                                            */
/* -------------------------------------------------------------------------- */

/***** MBWB_LCD_isBusy() - True while data is queued or being sent. *****/
bool MBWB_LCD_isBusy(void)
{
    return (MBWB_L_readReg(MBWB_LCD_BaseAddress, MBWB_LCD_STATUS_REG) &
            MBWB_LCD_STATUS_BUSY_MASK) != 0U;
}

/***** MBWB_LCD_waitIdle() - Wait until all queued data has been sent. *****/
void MBWB_LCD_waitIdle(void)
{
    while (MBWB_LCD_isBusy())
    {
        /* spin */
    }
}

/***** MBWB_LCD_flush() - Discard queued data and abort the current transfer. *****/
void MBWB_LCD_flush(void)
{
    MBWB_LCD_writeCtrl(MBWB_LCD_CtrlShadow | MBWB_LCD_CTRL_FLUSH_MASK);
}

/***** MBWB_LCD_enableIdleInterrupt() - Enable/disable the idle interrupt. *****/
void MBWB_LCD_enableIdleInterrupt(bool Enable)
{
    if (Enable)
    {
        MBWB_LCD_CtrlShadow |= MBWB_LCD_CTRL_IRQ_EN_MASK;
    }
    else
    {
        MBWB_LCD_CtrlShadow &= ~MBWB_LCD_CTRL_IRQ_EN_MASK;
    }

    MBWB_LCD_writeCtrl(MBWB_LCD_CtrlShadow);
}

/* -------------------------------------------------------------------------- */
/*  Low-level panel access                                                    */
/* -------------------------------------------------------------------------- */

/***** MBWB_LCD_writeCommand() - Queue one command byte. *****/
void MBWB_LCD_writeCommand(u8 Command)
{
    MBWB_L_writeReg(MBWB_LCD_BaseAddress, MBWB_LCD_CMD_REG, (u32)Command);
}

/***** MBWB_LCD_writeData() - Queue one data byte. *****/
void MBWB_LCD_writeData(u8 Data)
{
    MBWB_L_writeReg(MBWB_LCD_BaseAddress, MBWB_LCD_DATA8_REG, (u32)Data);
}

/***** MBWB_LCD_writeCommandData() - Queue a command and its parameters. *****/
void MBWB_LCD_writeCommandData(u8 Command, const u8 *Data, u32 Length)
{
    u32 Index;

    MBWB_LCD_writeCommand(Command);

    if (Data == NULL)
    {
        return;
    }

    for (Index = 0U; Index < Length; Index++)
    {
        MBWB_LCD_writeData(Data[Index]);
    }
}

/***** MBWB_LCD_setWindow() - Set the drawing window and start RAMWR. *****/
void MBWB_LCD_setWindow(u32 X0, u32 Y0, u32 X1, u32 Y1)
{
    MBWB_LCD_writeCommand(ST7796_CASET);
    MBWB_LCD_writeData((u8)(X0 >> 8U));
    MBWB_LCD_writeData((u8)X0);
    MBWB_LCD_writeData((u8)(X1 >> 8U));
    MBWB_LCD_writeData((u8)X1);

    MBWB_LCD_writeCommand(ST7796_RASET);
    MBWB_LCD_writeData((u8)(Y0 >> 8U));
    MBWB_LCD_writeData((u8)Y0);
    MBWB_LCD_writeData((u8)(Y1 >> 8U));
    MBWB_LCD_writeData((u8)Y1);

    MBWB_LCD_writeCommand(ST7796_RAMWR);
}

/***** MBWB_LCD_writePixels() - Queue pixels from a buffer. *****/
void MBWB_LCD_writePixels(const u16 *Pixels, u32 Count)
{
    u32 Index;

    if (Pixels == NULL)
    {
        return;
    }

    for (Index = 0U; Index < Count; Index++)
    {
        MBWB_L_writeReg(MBWB_LCD_BaseAddress, MBWB_LCD_DATA16_REG,
                        (u32)Pixels[Index]);
    }
}

/***** MBWB_LCD_writeColor() - Queue Count copies of one color. *****/
void MBWB_LCD_writeColor(u16 Color, u32 Count)
{
    while (Count != 0U)
    {
        u32 Chunk = (Count > MBWB_LCD_FILLCNT_MASK) ? MBWB_LCD_FILLCNT_MASK
                                                    : Count;

        if (Chunk == 1U)
        {
            MBWB_L_writeReg(MBWB_LCD_BaseAddress, MBWB_LCD_DATA16_REG,
                            (u32)Color);
        }
        else
        {
            MBWB_LCD_setFillCount(Chunk);
            MBWB_L_writeReg(MBWB_LCD_BaseAddress, MBWB_LCD_FILL_REG,
                            (u32)Color);
        }

        Count -= Chunk;
    }
}

/* -------------------------------------------------------------------------- */
/*  Graphics                                                                  */
/* -------------------------------------------------------------------------- */

/***** MBWB_LCD_fillScreen() - Fill the whole screen. *****/
void MBWB_LCD_fillScreen(u16 Color)
{
    MBWB_LCD_fillRect(0, 0, MBWB_LCD_Width, MBWB_LCD_Height, Color);
}

/***** MBWB_LCD_drawPixel() - Draw a single pixel. *****/
void MBWB_LCD_drawPixel(s32 X, s32 Y, u16 Color)
{
    if ((X < 0) || (Y < 0) || (X >= MBWB_LCD_Width) || (Y >= MBWB_LCD_Height))
    {
        return;
    }

    MBWB_LCD_setWindow((u32)X, (u32)Y, (u32)X, (u32)Y);
    MBWB_L_writeReg(MBWB_LCD_BaseAddress, MBWB_LCD_DATA16_REG, (u32)Color);
}

/***** MBWB_LCD_drawHLine() - Draw a horizontal line. *****/
void MBWB_LCD_drawHLine(s32 X, s32 Y, s32 Width, u16 Color)
{
    MBWB_LCD_fillRect(X, Y, Width, 1, Color);
}

/***** MBWB_LCD_drawVLine() - Draw a vertical line. *****/
void MBWB_LCD_drawVLine(s32 X, s32 Y, s32 Height, u16 Color)
{
    MBWB_LCD_fillRect(X, Y, 1, Height, Color);
}

/***** MBWB_LCD_drawLine() - Draw a line between two points. *****/
void MBWB_LCD_drawLine(s32 X0, s32 Y0, s32 X1, s32 Y1, u16 Color)
{
    s32 Dx, Dy, Sx, Sy, Err;

    if (Y0 == Y1)
    {
        if (X1 < X0) { s32 T = X0; X0 = X1; X1 = T; }
        MBWB_LCD_drawHLine(X0, Y0, X1 - X0 + 1, Color);
        return;
    }

    if (X0 == X1)
    {
        if (Y1 < Y0) { s32 T = Y0; Y0 = Y1; Y1 = T; }
        MBWB_LCD_drawVLine(X0, Y0, Y1 - Y0 + 1, Color);
        return;
    }

    Dx  = (X1 > X0) ? (X1 - X0) : (X0 - X1);
    Dy  = (Y1 > Y0) ? (Y0 - Y1) : (Y1 - Y0);   /* negative */
    Sx  = (X0 < X1) ? 1 : -1;
    Sy  = (Y0 < Y1) ? 1 : -1;
    Err = Dx + Dy;

    for (;;)
    {
        s32 E2;

        MBWB_LCD_drawPixel(X0, Y0, Color);

        if ((X0 == X1) && (Y0 == Y1))
        {
            break;
        }

        E2 = 2 * Err;

        if (E2 >= Dy)
        {
            Err += Dy;
            X0  += Sx;
        }

        if (E2 <= Dx)
        {
            Err += Dx;
            Y0  += Sy;
        }
    }
}

/***** MBWB_LCD_drawRect() - Draw a rectangle outline. *****/
void MBWB_LCD_drawRect(s32 X, s32 Y, s32 Width, s32 Height, u16 Color)
{
    if ((Width <= 0) || (Height <= 0))
    {
        return;
    }

    MBWB_LCD_drawHLine(X, Y, Width, Color);
    MBWB_LCD_drawHLine(X, Y + Height - 1, Width, Color);
    MBWB_LCD_drawVLine(X, Y, Height, Color);
    MBWB_LCD_drawVLine(X + Width - 1, Y, Height, Color);
}

/***** MBWB_LCD_fillRect() - Draw a filled rectangle. *****/
void MBWB_LCD_fillRect(s32 X, s32 Y, s32 Width, s32 Height, u16 Color)
{
    if (!MBWB_LCD_clipRect(&X, &Y, &Width, &Height))
    {
        return;
    }

    MBWB_LCD_setWindow((u32)X, (u32)Y,
                       (u32)(X + Width - 1), (u32)(Y + Height - 1));
    MBWB_LCD_writeColor(Color, (u32)Width * (u32)Height);
}

/***** MBWB_LCD_drawCircle() - Draw a circle outline (midpoint algorithm). *****/
void MBWB_LCD_drawCircle(s32 X0, s32 Y0, s32 Radius, u16 Color)
{
    s32 X = Radius;
    s32 Y = 0;
    s32 Err = 1 - Radius;

    if (Radius < 0)
    {
        return;
    }

    while (X >= Y)
    {
        MBWB_LCD_drawPixel(X0 + X, Y0 + Y, Color);
        MBWB_LCD_drawPixel(X0 + Y, Y0 + X, Color);
        MBWB_LCD_drawPixel(X0 - Y, Y0 + X, Color);
        MBWB_LCD_drawPixel(X0 - X, Y0 + Y, Color);
        MBWB_LCD_drawPixel(X0 - X, Y0 - Y, Color);
        MBWB_LCD_drawPixel(X0 - Y, Y0 - X, Color);
        MBWB_LCD_drawPixel(X0 + Y, Y0 - X, Color);
        MBWB_LCD_drawPixel(X0 + X, Y0 - Y, Color);

        Y++;

        if (Err < 0)
        {
            Err += (2 * Y) + 1;
        }
        else
        {
            X--;
            Err += 2 * (Y - X) + 1;
        }
    }
}

/***** MBWB_LCD_fillCircle() - Draw a filled circle. *****/
void MBWB_LCD_fillCircle(s32 X0, s32 Y0, s32 Radius, u16 Color)
{
    s32 Dy;
    s32 HalfWidth = Radius;
    const s32 RadiusSq = Radius * Radius;

    if (Radius < 0)
    {
        return;
    }

    /* One horizontal span per row; HalfWidth only shrinks as |Dy| grows. */
    for (Dy = 0; Dy <= Radius; Dy++)
    {
        while ((HalfWidth * HalfWidth) + (Dy * Dy) > RadiusSq)
        {
            HalfWidth--;
        }

        MBWB_LCD_drawHLine(X0 - HalfWidth, Y0 + Dy, (2 * HalfWidth) + 1, Color);

        if (Dy != 0)
        {
            MBWB_LCD_drawHLine(X0 - HalfWidth, Y0 - Dy, (2 * HalfWidth) + 1, Color);
        }
    }
}

/***** MBWB_LCD_drawImage() - Draw an RGB565 image. *****/
void MBWB_LCD_drawImage(s32 X, s32 Y, u32 Width, u32 Height,
                        const u16 *Pixels)
{
    s32 Cx = X;
    s32 Cy = Y;
    s32 Cw = (s32)Width;
    s32 Ch = (s32)Height;
    s32 Row;

    if ((Pixels == NULL) || !MBWB_LCD_clipRect(&Cx, &Cy, &Cw, &Ch))
    {
        return;
    }

    MBWB_LCD_setWindow((u32)Cx, (u32)Cy, (u32)(Cx + Cw - 1), (u32)(Cy + Ch - 1));

    for (Row = 0; Row < Ch; Row++)
    {
        const u16 *Src = Pixels + ((u32)(Cy - Y + Row) * Width) + (u32)(Cx - X);
        MBWB_LCD_writePixels(Src, (u32)Cw);
    }
}

/* -------------------------------------------------------------------------- */
/*  Text drawing at pixel coordinates                                         */
/* -------------------------------------------------------------------------- */

/***** MBWB_LCD_drawChar() - Draw one character. *****/
void MBWB_LCD_drawChar(s32 X, s32 Y, char Character,
                       u16 Foreground, u16 Background, u32 Scale)
{
    const u8 *Glyph = &MBWB_LCD_Font8x16[(u32)(u8)Character * MBWB_LCD_FONT_HEIGHT];
    s32 CellW, CellH;
    u32 GlyphRow, Repeat, Bit, Dup;

    if (Scale == 0U)
    {
        Scale = 1U;
    }

    CellW = (s32)(MBWB_LCD_FONT_WIDTH * Scale);
    CellH = (s32)(MBWB_LCD_FONT_HEIGHT * Scale);

    if ((X >= MBWB_LCD_Width) || (Y >= MBWB_LCD_Height) ||
        (X + CellW <= 0) || (Y + CellH <= 0))
    {
        return;
    }

    if ((X < 0) || (Y < 0) ||
        (X + CellW > MBWB_LCD_Width) || (Y + CellH > MBWB_LCD_Height))
    {
        /* Partially visible: slow path with per-pixel clipping. */
        for (GlyphRow = 0U; GlyphRow < MBWB_LCD_FONT_HEIGHT; GlyphRow++)
        {
            for (Bit = 0U; Bit < MBWB_LCD_FONT_WIDTH; Bit++)
            {
                u16 Color = ((Glyph[GlyphRow] & (0x80U >> Bit)) != 0U)
                            ? Foreground : Background;
                MBWB_LCD_fillRect(X + (s32)(Bit * Scale),
                                  Y + (s32)(GlyphRow * Scale),
                                  (s32)Scale, (s32)Scale, Color);
            }
        }
        return;
    }

    /* Fully visible: one window, stream the cell. */
    MBWB_LCD_setWindow((u32)X, (u32)Y, (u32)(X + CellW - 1), (u32)(Y + CellH - 1));

    for (GlyphRow = 0U; GlyphRow < MBWB_LCD_FONT_HEIGHT; GlyphRow++)
    {
        const u8 Bits = Glyph[GlyphRow];

        for (Repeat = 0U; Repeat < Scale; Repeat++)
        {
            for (Bit = 0U; Bit < MBWB_LCD_FONT_WIDTH; Bit++)
            {
                const u32 Color = ((Bits & (0x80U >> Bit)) != 0U)
                                  ? (u32)Foreground : (u32)Background;

                for (Dup = 0U; Dup < Scale; Dup++)
                {
                    MBWB_L_writeReg(MBWB_LCD_BaseAddress,
                                    MBWB_LCD_DATA16_REG, Color);
                }
            }
        }
    }
}

/***** MBWB_LCD_drawString() - Draw a string at pixel coordinates. *****/
void MBWB_LCD_drawString(s32 X, s32 Y, const char *String,
                         u16 Foreground, u16 Background, u32 Scale)
{
    if (String == NULL)
    {
        return;
    }

    if (Scale == 0U)
    {
        Scale = 1U;
    }

    while (*String != '\0')
    {
        MBWB_LCD_drawChar(X, Y, *String, Foreground, Background, Scale);
        X += (s32)(MBWB_LCD_FONT_WIDTH * Scale);
        String++;
    }
}

/* -------------------------------------------------------------------------- */
/*  Text console                                                              */
/* -------------------------------------------------------------------------- */

/***** MBWB_LCD_setTextColors() - Set the console colors. *****/
void MBWB_LCD_setTextColors(u16 Foreground, u16 Background)
{
    MBWB_LCD_TextFg = Foreground;
    MBWB_LCD_TextBg = Background;
}

/***** MBWB_LCD_setTextScale() - Set the console text scale. *****/
void MBWB_LCD_setTextScale(u32 Scale)
{
    MBWB_LCD_TextScale = (Scale == 0U) ? 1U : Scale;
    MBWB_LCD_home();
}

/***** MBWB_LCD_getTextCols() - Number of console columns. *****/
u32 MBWB_LCD_getTextCols(void)
{
    return (u32)MBWB_LCD_Width / (MBWB_LCD_FONT_WIDTH * MBWB_LCD_TextScale);
}

/***** MBWB_LCD_getTextRows() - Number of console rows. *****/
u32 MBWB_LCD_getTextRows(void)
{
    return (u32)MBWB_LCD_Height / (MBWB_LCD_FONT_HEIGHT * MBWB_LCD_TextScale);
}

/***** MBWB_LCD_clear() - Clear the screen and home the cursor. *****/
void MBWB_LCD_clear(void)
{
    MBWB_LCD_fillScreen(MBWB_LCD_TextBg);
    MBWB_LCD_home();
}

/***** MBWB_LCD_setCursor() - Set the console cursor. *****/
void MBWB_LCD_setCursor(u32 Row, u32 Col)
{
    if (Row < MBWB_LCD_getTextRows())
    {
        MBWB_LCD_CursorRow = Row;
    }

    if (Col < MBWB_LCD_getTextCols())
    {
        MBWB_LCD_CursorCol = Col;
    }
}

/***** MBWB_LCD_getCursor() - Get the console cursor. *****/
void MBWB_LCD_getCursor(u32 *Row, u32 *Col)
{
    if (Row != NULL)
    {
        *Row = MBWB_LCD_CursorRow;
    }

    if (Col != NULL)
    {
        *Col = MBWB_LCD_CursorCol;
    }
}

/***** MBWB_LCD_home() - Move the console cursor home. *****/
void MBWB_LCD_home(void)
{
    MBWB_LCD_CursorRow = 0U;
    MBWB_LCD_CursorCol = 0U;
}

/***** MBWB_LCD_putChar() - Write one character at the console cursor. *****/
void MBWB_LCD_putChar(char Character)
{
    if (Character == '\n')
    {
        MBWB_LCD_newLine();
        return;
    }

    if (Character == '\r')
    {
        MBWB_LCD_CursorCol = 0U;
        return;
    }

    MBWB_LCD_drawChar(
        (s32)(MBWB_LCD_CursorCol * MBWB_LCD_FONT_WIDTH * MBWB_LCD_TextScale),
        (s32)(MBWB_LCD_CursorRow * MBWB_LCD_FONT_HEIGHT * MBWB_LCD_TextScale),
        Character, MBWB_LCD_TextFg, MBWB_LCD_TextBg, MBWB_LCD_TextScale);

    MBWB_LCD_CursorCol++;

    if (MBWB_LCD_CursorCol >= MBWB_LCD_getTextCols())
    {
        MBWB_LCD_newLine();
    }
}

/***** MBWB_LCD_putString() - Write a string at the console cursor. *****/
void MBWB_LCD_putString(const char *String)
{
    if (String == NULL)
    {
        return;
    }

    while (*String != '\0')
    {
        MBWB_LCD_putChar(*String);
        String++;
    }
}

/***** MBWB_LCD_printf() - Formatted console output. *****/
void MBWB_LCD_printf(const char *Format, ...)
{
    va_list Arguments;

    if (Format == NULL)
    {
        return;
    }

    va_start(Arguments, Format);

    while (*Format != '\0')
    {
        if (*Format != '%')
        {
            MBWB_LCD_putChar(*Format);
            Format++;
            continue;
        }

        Format++;

        if (*Format == '%')
        {
            MBWB_LCD_putChar('%');
            Format++;
            continue;
        }

        {
            bool ZeroPad = false;
            u32 Width = 0U;
            char Conversion;

            if (*Format == '0')
            {
                ZeroPad = true;
                Format++;
            }

            while ((*Format >= '0') && (*Format <= '9'))
            {
                Width = (Width * 10U) + (u32)(*Format - '0');
                Format++;
            }

            Conversion = *Format;

            if (Conversion == '\0')
            {
                break;
            }

            switch (Conversion)
            {
                case 'c':
                    MBWB_LCD_putChar((char)va_arg(Arguments, int));
                    break;

                case 's':
                {
                    const char *String = va_arg(Arguments, const char *);
                    const char *Shown = (String == NULL) ? "(null)" : String;
                    u32 Length = MBWB_LCD_strlen(Shown);

                    while (Length < Width)
                    {
                        MBWB_LCD_putChar(' ');
                        Length++;
                    }

                    MBWB_LCD_putString(Shown);
                    break;
                }

                case 'd':
                case 'i':
                    MBWB_LCD_putSigned((s32)va_arg(Arguments, int),
                                       Width, ZeroPad ? '0' : ' ');
                    break;

                case 'u':
                    MBWB_LCD_putUnsigned((u32)va_arg(Arguments, unsigned int),
                                         10U, false, Width,
                                         ZeroPad ? '0' : ' ');
                    break;

                case 'x':
                case 'X':
                    MBWB_LCD_putUnsigned((u32)va_arg(Arguments, unsigned int),
                                         16U, (Conversion == 'X'), Width,
                                         ZeroPad ? '0' : ' ');
                    break;

                case 'p':
                    MBWB_LCD_putString("0x");
                    MBWB_LCD_putUnsigned((u32)(UINTPTR)va_arg(Arguments, void *),
                                         16U, false,
                                         (Width == 0U) ? 8U : Width, '0');
                    break;

                default:
                    MBWB_LCD_putChar('%');
                    MBWB_LCD_putChar(Conversion);
                    break;
            }

            Format++;
        }
    }

    va_end(Arguments);
}

/* -------------------------------------------------------------------------- */
/*  Private helper-function definitions                                       */
/* -------------------------------------------------------------------------- */

/**
 * @brief Write LCD_CTRL. The FLUSH bit is self-clearing in hardware.
 */
static void MBWB_LCD_writeCtrl(u32 Value)
{
    MBWB_L_writeReg(MBWB_LCD_BaseAddress, MBWB_LCD_CTRL_REG, Value);
}

/**
 * @brief Update LCD_FILLCNT only if it differs from the last value written.
 *
 * The count is captured into each FIFO entry when LCD_FILL is written, so it
 * is safe to change it while earlier fills are still queued.
 */
static void MBWB_LCD_setFillCount(u32 Count)
{
    if (Count != MBWB_LCD_FillCount)
    {
        MBWB_LCD_FillCount = Count;
        MBWB_L_writeReg(MBWB_LCD_BaseAddress, MBWB_LCD_FILLCNT_REG, Count);
    }
}

/**
 * @brief Clip a rectangle to the screen.
 *
 * @return true if any part of the rectangle is visible.
 */
static bool MBWB_LCD_clipRect(s32 *X, s32 *Y, s32 *Width, s32 *Height)
{
    s32 X1 = *X + *Width;    /* exclusive */
    s32 Y1 = *Y + *Height;

    if ((*Width <= 0) || (*Height <= 0))
    {
        return false;
    }

    if (*X < 0)               { *X = 0; }
    if (*Y < 0)               { *Y = 0; }
    if (X1 > MBWB_LCD_Width)  { X1 = MBWB_LCD_Width; }
    if (Y1 > MBWB_LCD_Height) { Y1 = MBWB_LCD_Height; }

    if ((X1 <= *X) || (Y1 <= *Y))
    {
        return false;
    }

    *Width  = X1 - *X;
    *Height = Y1 - *Y;
    return true;
}

/**
 * @brief Move the console cursor to the start of the next row (wrapping to the
 *        top) and clear that row.
 */
static void MBWB_LCD_newLine(void)
{
    MBWB_LCD_CursorCol = 0U;
    MBWB_LCD_CursorRow++;

    if (MBWB_LCD_CursorRow >= MBWB_LCD_getTextRows())
    {
        MBWB_LCD_CursorRow = 0U;
    }

    MBWB_LCD_clearTextRow(MBWB_LCD_CursorRow);
}

/**
 * @brief Fill one console text row with the background color.
 */
static void MBWB_LCD_clearTextRow(u32 Row)
{
    const s32 RowHeight = (s32)(MBWB_LCD_FONT_HEIGHT * MBWB_LCD_TextScale);

    MBWB_LCD_fillRect(0, (s32)Row * RowHeight, MBWB_LCD_Width, RowHeight,
                      MBWB_LCD_TextBg);
}

/**
 * @brief Write an unsigned integer in the given base with left padding.
 */
static void MBWB_LCD_putUnsigned(u32 Value, u32 Base, bool Uppercase,
                                 u32 Width, char PadChar)
{
    char Buffer[33];
    u32 NumDigits = 0U;
    const char *Digits = Uppercase ? "0123456789ABCDEF" : "0123456789abcdef";

    if ((Base < 2U) || (Base > 16U))
    {
        return;
    }

    do
    {
        Buffer[NumDigits] = Digits[Value % Base];
        NumDigits++;
        Value /= Base;
    } while ((Value != 0U) && (NumDigits < (u32)sizeof(Buffer)));

    while (NumDigits < Width)
    {
        MBWB_LCD_putChar(PadChar);
        Width--;
    }

    while (NumDigits > 0U)
    {
        NumDigits--;
        MBWB_LCD_putChar(Buffer[NumDigits]);
    }
}

/**
 * @brief Write a signed decimal integer with left padding.
 */
static void MBWB_LCD_putSigned(s32 Value, u32 Width, char PadChar)
{
    u32 Magnitude;

    if (Value < 0)
    {
        MBWB_LCD_putChar('-');
        Magnitude = 0U - (u32)Value;

        if (Width > 0U)
        {
            Width--;
        }
    }
    else
    {
        Magnitude = (u32)Value;
    }

    MBWB_LCD_putUnsigned(Magnitude, 10U, false, Width, PadChar);
}

/**
 * @brief Length of a null-terminated string.
 */
static u32 MBWB_LCD_strlen(const char *String)
{
    u32 Length = 0U;

    while (String[Length] != '\0')
    {
        Length++;
    }

    return Length;
}
