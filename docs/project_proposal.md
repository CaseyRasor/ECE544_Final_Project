# ECE 544 Final Project Proposal

**Project name:** TBD
**Team:** Casey Rasor, Jeremiah Vandagrift

## Project description

**What it does:**
1. A user uploads an animal photo from a web page, cropped to 320×320.
2. An ESP32-S3 receives it over Wi-Fi and sends it to the FPGA over **SPI**.
3. A MicroBlaze SoC displays the image on an LCD and downscales it.
4. A **custom CNN accelerator** classifies the image.
5. The result is shown on the LCD and returned to the web page.

**Capabilities:**
- Wi-Fi and an HTTP web service.
- Image processing: crop, RGB565 conversion, downscaling.
- CNN inference in custom hardware.
- SPI link to the ESP32.
- An SPI display.
- Interrupts.

**Hardware:**
- Nexys A7-100T.
- ESP32-S3-DevKitC-1 (N16R8).
- 3.5" ST7796S 320×480 SPI LCD.
- Pmod cables and a proto board.

**Tools:**
- PlatformIO with ESP-IDF.
- Python ML framework (PyTorch or Keras, TBD).
- HTML/JavaScript.
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
- CNN training and 8-bit quantization.

**Work split:** still being decided. The work areas are FPGA hardware, CNN accelerator, CNN model, MicroBlaze software, ESP32 firmware, and the web page.

**Still to decide:**
- Where the web page is hosted.
- CNN classes and input size (32×32 to 80×80).
- ML framework.

**Demonstrating success:**
- A photo uploaded from a phone is displayed and correctly classified.
- Hardware results match a C reference model.
- Accelerator speedup over software inference is measured.

**If we run out of time:**
- Run the CNN in software on MicroBlaze.
- Accelerate only the convolution layers.
- Use a smaller network.
- Use preloaded images instead of the web page.

## Demo deliverables

**Committed:** web upload → ESP32 → SPI → FPGA. The image is displayed on the LCD, classified by the CNN accelerator, and the result is shown on the LCD and the web page.

**Stretch goals:**
- Full network in hardware.
- Top-3 predictions with confidence.
- On-screen comparison of hardware and software speed.
- ESP32 camera for live capture.

## Milestones

| Date | Target |
|---|---|
| Done | LCD peripheral and driver. ESP32 ↔ FPGA communication prototype. |
| Sun 22-Nov | Proposal submitted; open decisions made. |
| Week of 23-Nov | SPI image link: test image from the ESP32 shown on the LCD. CNN trained and quantized, with a C reference model. FreeRTOS application. |
| Fri 04-Dec | Wi-Fi upload → LCD end to end. Software CNN on MicroBlaze. Accelerator passing simulation. |
| Week of 07-Dec | Accelerator working on hardware. Result returned to the web page. Hardware on proto board. |
| Wed 09-Dec | Demo. |
| Thu 10-Dec | Deliverables submitted. |
