# ECE 544 Final Project Proposal

**Project name:** 2D Convolutional Neural Network Accelerator
**Team:** Casey Rasor, Jeremiah Vandagrift

## Project description

**What it does:**
1. A user uploads an animal photo from a web page, cropped to a 1:1 ratio then downsized to 320×320px.
2. An ESP32-S3 receives it over Wi-Fi and sends it to the FPGA over **SPI**.
3. A MicroBlaze SoC displays the image on an LCD and downscales it to be fed to the CNN.
4. A **custom CNN hardware accelerator** classifies the image.
5. The result is shown on the LCD and returned to the web page.

**Capabilities:**
- Wi-Fi and an HTTP web service.
- Image processing: crop, RGB565 (16-bit color depth) conversion, downscaling.
- CNN inference in custom hardware.
- SPI link to the ESP32.
- An SPI display.
- Interrupts.

**Hardware:**
- Nexys A7-100T.
- ESP32-S3-DevKitC-1 (N16R8).
- 4.0" ST7796S 320×480 SPI LCD.
- Pmod cables and a proto board.

**Tools:**
- PlatformIO with ESP-IDF.
- Python ML framework (PyTorch or Keras, TBD) for training only.
- HTML/JavaScript/Vite/Svelte.
- xsim.
- GitHub.

**OS:** FreeRTOS on the MicroBlaze.

## Design approach

**Custom hardware (Wishbone peripherals):**
- SPI LCD controller *(done)*.
- SPI slave link to the ESP32: images in, results out.
- CNN accelerator: int8 multiply-accumulate units, BRAM buffers.

**Software:**
- FreeRTOS application.
- Drivers *(LCD done)*.
- ESP32 firmware and web page.
- Test CNN software model training 

**Work split:** 
- The MicroBlaze firmware will and fixture soldering for hardware components be done by Casey Rasor.
- The CNN RTL module (including the software training program) and the ESP32 Firmware + Web App will be done by Jeremiah Vandagrift.

**Still to decide:**
- CNN classes and input size (32×32 to 80×80).
- ML framework.

**Demonstrating success:**
- A photo uploaded from a phone is displayed and correctly classified.
- Hardware results match a reference software model used for training.

**If we run out of time:**
- Run the CNN in software on MicroBlaze.
- Use a smaller network.
- Use preloaded images instead of the web page.

## Demo deliverables

**Committed:** web upload —> ESP32 —> SPI —> FPGA —> LCD Display. The image is displayed on the LCD, classified by the CNN accelerator, and the result is shown on the LCD and the web page.

**Stretch goals:**
- Camera Live Feed + Automatic Classification.

## Milestones

| Date | Target |
|---|---|
| Done | LCD peripheral and driver. ESP32 ↔ FPGA communication prototype. |
| Sun 22-Nov | Proposal submitted; open decisions made. |
| Week of 23-Nov | SPI image link: test image from the ESP32 shown on the LCD. CNN trained and quantized, with a C reference model. FreeRTOS application. |
| Fri 04-Dec | Wi-Fi upload → LCD end to end. Software CNN on MicroBlaze. Accelerator passing simulation. |
| Week of 07-Dec | Accelerator working on hardware. Result returned to the web page. Hardware on proto board. |
| Wed 09-Dec | /. |
| Thu 10-Dec | Deliverables submitted. |
