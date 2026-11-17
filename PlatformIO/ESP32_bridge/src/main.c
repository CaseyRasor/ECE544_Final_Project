/**
 * @file    main.c
 * @brief   ESP32-S3 <-> FPGA serial bridge (bring-up firmware).
 *
 * Text typed in the serial monitor (UART0, the board's "COM"/UART USB port)
 * is sent to the FPGA one line at a time over UART1. Anything the FPGA sends
 * back is printed to the serial monitor.
 *
 * UART1 wiring (ESP32-S3 DevKitC J1 header -> Nexys A7 Pmod JB):
 *
 *   GPIO4  UART1 CTS  (in)   <- JB3   ESP_RTS_N  (FPGA output)
 *   GPIO5  UART1 RTS  (out)  -> JB9   ESP_CTS_N  (FPGA input)
 *   GPIO6  UART1 RX   (in)   <- JB4   ESP_TXD    (FPGA output)
 *   GPIO7  UART1 TX   (out)  -> JB10  ESP_RXD    (FPGA input)
 *   GND                      -- JB5 or JB11
 *
 * Do not connect Pmod VCC; the ESP32 is powered from its own USB cable.
 *
 * Line format must match the FPGA: 8N1 at LINK_BAUD.
 */
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "driver/uart.h"
#include "driver/gpio.h"
#include "esp_log.h"

/* -------------------------------------------------------------------------- */
/*  Configuration                                                             */
/* -------------------------------------------------------------------------- */

#define LINK_UART           UART_NUM_1
#define LINK_BAUD           115200          /* must match TEST_ESP_LINK_BAUD  */
#define LINK_PIN_CTS        4
#define LINK_PIN_RTS        5
#define LINK_PIN_RX         6
#define LINK_PIN_TX         7

/*
 * RTS/CTS flow control on the ESP32 side. Safe to leave on even while the FPGA
 * has flow control off: the FPGA then holds ESP_RTS_N low (always ready) and
 * ignores our RTS. Requires the GPIO4 (CTS) wire - if it is missing the pin
 * floats and transmission may stop. Set to 0 to run with TX/RX/GND only.
 */
#define LINK_FLOW_CONTROL   1
#define LINK_RTS_THRESH     100             /* bytes in 128-byte HW FIFO      */

#define LINK_RX_BUF         4096
#define LINK_TX_BUF         2048

#define CON_UART            UART_NUM_0      /* serial monitor                 */
#define CON_BAUD            115200
#define CON_RX_BUF          1024

#define LINE_LEN            256
#define FPGA_LINE_IDLE_MS   50              /* flush a partial FPGA line      */

static const char *TAG = "bridge";

/* -------------------------------------------------------------------------- */
/*  Console output                                                            */
/* -------------------------------------------------------------------------- */

/* Both tasks print to the console; the mutex keeps their output separate and
 * protects the line being typed so it can be redrawn after FPGA output. */
static SemaphoreHandle_t con_lock;
static char   edit_line[LINE_LEN];
static size_t edit_len;

static void con_write(const char *s, size_t n)
{
    uart_write_bytes(CON_UART, s, n);
}

static void con_puts(const char *s)
{
    con_write(s, strlen(s));
}

static void con_prompt(void)
{
    con_puts("> ");
    con_write(edit_line, edit_len);
}

/* Write printable text; show other bytes as \xNN so binary is visible. */
static void con_write_escaped(const char *s, size_t n)
{
    char hex[5];
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c >= 0x20 && c < 0x7F) {
            con_write((const char *)&c, 1);
        } else if (c != '\r' && c != '\n') {
            snprintf(hex, sizeof hex, "\\x%02X", c);
            con_puts(hex);
        }
    }
}

/* -------------------------------------------------------------------------- */
/*  Serial monitor -> FPGA                                                    */
/* -------------------------------------------------------------------------- */

static void console_task(void *arg)
{
    (void)arg;
    uint8_t buf[64];
    bool    last_cr = false;
    uint32_t sent = 0;

    for (;;) {
        /* uart_read_bytes() waits until it has *all* the requested bytes, so
         * block for one byte, then take whatever else is already waiting. */
        int n = uart_read_bytes(CON_UART, buf, 1, portMAX_DELAY);
        if (n <= 0) {
            continue;
        }
        int more = uart_read_bytes(CON_UART, buf + 1, sizeof buf - 1, 0);
        if (more > 0) {
            n += more;
        }

        xSemaphoreTake(con_lock, portMAX_DELAY);
        for (int i = 0; i < n; i++) {
            char c = (char)buf[i];

            if (c == '\n' && last_cr) {         /* CR LF: LF already handled */
                last_cr = false;
                continue;
            }
            last_cr = (c == '\r');

            if (c == '\r' || c == '\n') {
                con_puts("\r\n");
                if (edit_len > 0) {
                    uart_write_bytes(LINK_UART, edit_line, edit_len);
                    uart_write_bytes(LINK_UART, "\r\n", 2);
                    sent++;
                    char msg[48];
                    snprintf(msg, sizeof msg, "[ESP32 -> FPGA] #%lu sent (%u bytes)\r\n",
                             (unsigned long)sent, (unsigned)edit_len + 2);
                    con_puts(msg);
                    edit_len = 0;
                }
                con_prompt();
            } else if (c == '\b' || c == 0x7F) {  /* backspace / delete */
                if (edit_len > 0) {
                    edit_len--;
                    con_puts("\b \b");
                }
            } else if (c >= 0x20 && c < 0x7F) {
                if (edit_len < LINE_LEN - 2) {    /* leave room for CR LF */
                    edit_line[edit_len++] = c;
                    con_write(&c, 1);             /* local echo */
                }
            }
            /* other control characters are ignored */
        }
        xSemaphoreGive(con_lock);
    }
}

/* -------------------------------------------------------------------------- */
/*  FPGA -> serial monitor                                                    */
/* -------------------------------------------------------------------------- */

static void fpga_print_line(const char *line, size_t len)
{
    xSemaphoreTake(con_lock, portMAX_DELAY);
    con_puts("\r\x1b[K");                       /* erase the prompt line */
    con_puts("[FPGA -> ESP32] ");
    con_write_escaped(line, len);
    con_puts("\r\n");
    con_prompt();                               /* redraw what was typed */
    xSemaphoreGive(con_lock);
}

static void link_rx_task(void *arg)
{
    (void)arg;
    static char line[LINE_LEN];
    size_t  len = 0;
    uint8_t buf[128];

    for (;;) {
        int n = uart_read_bytes(LINK_UART, buf, sizeof buf,
                                pdMS_TO_TICKS(FPGA_LINE_IDLE_MS));

        if (n <= 0) {
            /* Line went idle with a partial line pending: print it. */
            if (len > 0) {
                fpga_print_line(line, len);
                len = 0;
            }
            continue;
        }

        for (int i = 0; i < n; i++) {
            char c = (char)buf[i];
            if (c == '\n') {
                fpga_print_line(line, len);
                len = 0;
            } else if (c == '\r') {
                /* dropped; '\n' ends the line */
            } else {
                line[len++] = c;
                if (len == sizeof line) {
                    fpga_print_line(line, len);
                    len = 0;
                }
            }
        }
    }
}

/* -------------------------------------------------------------------------- */
/*  Setup                                                                     */
/* -------------------------------------------------------------------------- */

static void link_uart_init(void)
{
    const uart_config_t cfg = {
        .baud_rate           = LINK_BAUD,
        .data_bits           = UART_DATA_8_BITS,
        .parity              = UART_PARITY_DISABLE,
        .stop_bits           = UART_STOP_BITS_1,
#if LINK_FLOW_CONTROL
        .flow_ctrl           = UART_HW_FLOWCTRL_CTS_RTS,
#else
        .flow_ctrl           = UART_HW_FLOWCTRL_DISABLE,
#endif
        .rx_flow_ctrl_thresh = LINK_RTS_THRESH,
        .source_clk          = UART_SCLK_DEFAULT,
    };

    ESP_ERROR_CHECK(uart_driver_install(LINK_UART, LINK_RX_BUF, LINK_TX_BUF,
                                        0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(LINK_UART, &cfg));
#if LINK_FLOW_CONTROL
    ESP_ERROR_CHECK(uart_set_pin(LINK_UART, LINK_PIN_TX, LINK_PIN_RX,
                                 LINK_PIN_RTS, LINK_PIN_CTS));
#else
    ESP_ERROR_CHECK(uart_set_pin(LINK_UART, LINK_PIN_TX, LINK_PIN_RX,
                                 UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
#endif
    /* Keep RX high if the FPGA is not configured yet (avoids break/garbage). */
    gpio_pullup_en(LINK_PIN_RX);
}

static void console_uart_init(void)
{
    const uart_config_t cfg = {
        .baud_rate  = CON_BAUD,
        .data_bits  = UART_DATA_8_BITS,
        .parity     = UART_PARITY_DISABLE,
        .stop_bits  = UART_STOP_BITS_1,
        .flow_ctrl  = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };

    /* UART0 is already the log console; installing the driver lets us read
     * input with uart_read_bytes(). Let any pending log text finish first so
     * reconfiguring does not corrupt it. */
    uart_wait_tx_idle_polling(CON_UART);
    ESP_ERROR_CHECK(uart_driver_install(CON_UART, CON_RX_BUF, 0, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(CON_UART, &cfg));
}

void app_main(void)
{
    con_lock = xSemaphoreCreateMutex();

    ESP_LOGI(TAG, "UART1 link: %d baud 8N1, TX=GPIO%d RX=GPIO%d RTS=GPIO%d CTS=GPIO%d, flow control %s",
             LINK_BAUD, LINK_PIN_TX, LINK_PIN_RX, LINK_PIN_RTS, LINK_PIN_CTS,
             LINK_FLOW_CONTROL ? "on" : "off");

    console_uart_init();
    link_uart_init();

    /* Drop anything received while the FPGA was configuring. */
    uart_flush_input(LINK_UART);

    con_puts("\r\nESP32-S3 <-> FPGA bridge. Type a line and press Enter.\r\n");
    con_prompt();

    xTaskCreate(link_rx_task, "link_rx", 4096, NULL, 6, NULL);
    xTaskCreate(console_task, "console", 4096, NULL, 5, NULL);
}
