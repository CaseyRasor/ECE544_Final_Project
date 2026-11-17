# ECE544 Final Project — FPGA + ESP32 Image Classifier

A MicroBlaze system on a **Nexys A7-100T** with custom Wishbone peripherals:

- an **ST7796S SPI LCD**;
- a **UART link to an ESP32-S3**, which acts as a Wi-Fi co-processor.

**End goal:** the ESP32 receives animal images over Wi-Fi and sends them to the FPGA. A CNN on the FPGA classifies each image, and the result goes back to the ESP32 and is shown on the LCD.

**Current state:**
- The LCD peripheral and driver work on hardware.
- The ESP32 UART peripheral and driver pass simulation and the loopback self-test.
- Text typed into the ESP32's serial monitor is forwarded to the FPGA, which replies.

```
 PC serial monitor ──USB──► ESP32-S3 ──UART1 (Pmod JB)──► wb_esp ─┐
                                                                  │ Wishbone
 MicroBlaze ──AXI-Lite──► axlite2wbsp bridge ──► wb_mux ──────────┼─► wb_boardio / wb_sevenseg
                                                                  └─► wb_lcd ──SPI (Pmod JA)──► ST7796S LCD
```

## Repository layout

| Path | Contents |
|---|---|
| `hdl/` | RTL. Top level is `mbc_wb_nexys4DDR.sv`. |
| `hdl/wishbone/` | `wb_subsystem` (instantiates every peripheral), `wb_mux` (8-region address decoder), `wb_err` |
| `hdl/lcd/` | `wb_lcd` registers, `lcd_spi_engine` (custom SPI, not Xilinx IP), `lcd_fifo` (BRAM FIFO, also used by `wb_esp`) |
| `hdl/esp/` | `wb_esp` (UART with 4 KB RX / 1 KB TX FIFOs, RTS/CTS, IRQ), `esp_uart_rx`, `esp_uart_tx` |
| `hdl/boardio/`, `hdl/sevenseg/`, `hdl/cdc/` | Board switches, buttons, LEDs; seven-segment display; reset synchronizer |
| `hdl/vga/` | Legacy VGA peripheral the LCD replaced. **Not in the Vivado project.** |
| `constraints/` | `mbc_wb_nexys4DDR_lcd.xdc`, the only constraints file (pinout below) |
| `final_project.xpr` | Vivado project. It references `hdl/` and `constraints/` in place. |
| `final_project.srcs/` | Block design `mbc_wb_embsys.bd` (MicroBlaze, INTC, timers, UART Lite, AXI→WB bridge) and the IP `.xci` files |
| `mbc_wb_nexys4DDR.xsa` | Exported hardware, bitstream included. Build the Vitis platform from this. |
| `sw/mbc_wb_drivers/` | C drivers: `MBWB_HW.h` (address map, register bits), `MBWB_LCD`, `MBWB_ESP`, `MBWB_BIO`, `MBWB_SSEG` |
| `sw/apps/` | Test applications: `test_mbwb_lcd.c`, `test_mbwb_esp.c` |
| `sw/tools/make_lcd_font.py` | Generates `MBWB_LCD_font.c` |
| `sim/` | xsim testbenches. `run_sim.bat` runs the full Wishbone system; `esp/run_sim_esp.bat` runs `wb_esp` with an ESP32 model. |
| `PlatformIO/ESP32_bridge/` | ESP32-S3 firmware (ESP-IDF): bridges the USB serial console (UART0) to the FPGA (UART1) |

## Hardware

### Address map
The bridge occupies **0x8000_0000 – 0x8007_FFFF**. Each region is 64 KB, selected by `addr[18:16]`.

| Region | Base | Peripheral | IRQ (INTC input) |
|---|---|---|---|
| 0 | 0x8000_0000 | Board I/O | `wb_irq0` → 2 |
| 1 | 0x8001_0000 | Seven-segment | — |
| 2 | 0x8002_0000 | Error slave (reads `0xDEADBEEF`) | — |
| 3 | 0x8003_0000 | LCD | `wb_irq1` → 3 |
| 4 | 0x8004_0000 | ESP32 UART | `wb_irq2` → 5 |
| 5–7 | 0x8005_0000+ | Free (error slave) | — |

Other INTC inputs: 0 and 1 are the AXI timers, 4 is the UART Lite. Inputs 2–5 are rising-edge triggered.

To add a peripheral:
1. Add a slave port to `wb_mux.sv`. Its header has the steps.
2. Instantiate the peripheral in `wb_subsystem.sv`.
3. Add its base address to `MBWB_HW.h`.

Register maps for every peripheral are in `sw/mbc_wb_drivers/include/MBWB_HW.h`.

### Wiring
Both connections use 2x5 connectors over Pmod pins 2–4 / 8–10 plus VCC/GND; pins 1/7 are unused.

| LCD pin | Pmod JA | | ESP32-S3 | Pmod JB | FPGA signal |
|---|---|---|---|---|---|
| CS | JA4 | | GPIO4 (UART1 CTS) | JB3 | `ESP_RTS_N` |
| RST | JA10 | | GPIO5 (UART1 RTS) | JB9 | `ESP_CTS_N` |
| RS (D/C) | JA3 | | GPIO6 (UART1 RX) | JB4 | `ESP_TXD` |
| SDI (MOSI) | JA9 | | GPIO7 (UART1 TX) | JB10 | `ESP_RXD` |
| SCK | JA2 | | GND | JB5 / JB11 | GND |
| LED | JA8 | | | | |
| VCC / GND | JA VCC / GND | | | | |

The LCD's MISO pin is not connected.

> **Do not connect Pmod VCC to the ESP32.** It is powered from its own USB cable. Only GND is shared.

## Building

**Tools:** Vivado / Vitis 2026.1, and VS Code with the PlatformIO extension.

### 1. FPGA (Vivado)
> **Prerequisite:** the block design uses the mbc_wb custom IP (`axlite2wbsp`). Vivado looks for it in the IP repository path configured in the project. If the block design reports missing IP, point *Settings → IP → Repository* at your copy of the mbc_wb `ip_repo`.

1. Open `final_project.xpr`.
2. Select `mbc_wb_embsys.bd` and run *Generate Output Products*.
3. Run *Generate Bitstream*.
4. Run *File → Export → Export Hardware* (include the bitstream). This overwrites `mbc_wb_nexys4DDR.xsa`.

You can skip this step if you're only writing software: the committed `.xsa` is up to date.

### 2. MicroBlaze software (Vitis)
Platforms and applications aren't in the repo; create them from the sources:

1. Open this folder (or any folder) as a Vitis workspace.
2. Create a platform from `mbc_wb_nexys4DDR.xsa` (standalone OS, `microblaze_0`).
3. Create an *Empty Application* on that platform. In its `src/UserConfig.cmake`, add:
   - include directory: `sw/mbc_wb_drivers/include`
   - sources: everything in `sw/mbc_wb_drivers/source/` plus one app from `sw/apps/`

   The default stack and heap sizes are enough.
4. Build, program the FPGA, and run. Output appears on the Nexys A7's USB-UART at 115200 baud.

`test_mbwb_esp.c` runs a loopback self-test first, then enters link mode. In link mode it prints each line it receives from the ESP32 and sends back `FPGA got n bytes: ...`.

### 3. ESP32-S3 firmware (PlatformIO)
1. Open `PlatformIO/ESP32_bridge` in VS Code.
2. Plug the board in using its **COM/UART** USB port (CH343 chip), not the native "USB" port.
3. Set `upload_port` / `monitor_port` in `platformio.ini` if PlatformIO chooses the wrong COM port. It can pick the Nexys A7 by mistake.
4. Click **Upload**, then **Monitor**. Type a line and press Enter: it's sent to the FPGA, and the FPGA's reply is printed.

The pins, baud rate (115200) and flow-control setting are at the top of `src/main.c`, and they must match `TEST_ESP_LINK_BAUD` / `TEST_ESP_FLOW_CONTROL` in `sw/apps/test_mbwb_esp.c`.

### Simulation
Run `sim\run_sim.bat` (full Wishbone subsystem) or `sim\esp\run_sim_esp.bat` (`wb_esp`, 14 tests). Each runs xsim in batch mode and ends with `TEST PASSED`. If Vivado isn't installed in `C:\AMDDesignTools\2026.1`, edit `VIVADO_BIN` at the top of each `.bat` file first.
