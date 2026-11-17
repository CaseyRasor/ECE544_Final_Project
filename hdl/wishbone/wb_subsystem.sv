/**
 * @file	wb_subsystem.sv
 * @brief	SystemVerilog wrapper for multiple WB bus peripherals
 *
 * @author	Roy Kravitz (roy.kravitz@pdx.edu) and CoPilot
 * @date	13-Jun-2026
 * @version	1.0
 *
 * @detail
 * Verilog wrapper for the custom wb bus peripherals.  Connects to axi2wbsp,
 * the AXI-Wishbone bus bridge.  This is just a wrapper.  Each peripheral has its own logic.  
 *
 * This specific wrapper supports these wishbone peripherals (see wb_mux.sv for the region map):
 *	o Parameterized boardio - leds, switches, buttons, rgb_leds (customized by board type)
 *	o Seven-segment display controller
 *	o ST7796S SPI TFT LCD controller (replaces the 80 x 30 text VGA)
 *	o ESP32 UART link (Wi-Fi co-processor)
 * and the wb_err peripheral which generates an wb acknowledge if no other peripheral is addressed
 *
 * Interrupts: o_irq0 = board I/O, o_irq1 = LCD, o_irq2 = ESP32 UART
 *
 * This wrapper is customized for the Digilent Nexys A7 (Nexys 4 DDR) board
 * 
 */

`default_nettype wire

module wb_subsystem (
    // system clock and reset (CPU, AXI, and WB bus)
    i_clk,
    i_reset,
    
    // Wishbone controller interface (from axil2wbsp)
    i_wb_cyc,
    i_wb_stb,
    i_wb_we,
    i_wb_addr,
    i_wb_data,
    i_wb_sel,
    o_wb_ack,
    o_wb_data,
    
    // (Optional) interrupt outputs
    o_irq0, o_irq1, o_irq2,

    // board IO (switches, buttons, leds, RGB leds
    btns,
    sw,
    leds,
    rgb1RGB,
    rgb2RGB,
    
    // 7 segment display controller outputs
    AN,
    DP,
    Digits_Bits,
    
    // ST7796S LCD outputs
    LCD_SCLK, LCD_MOSI, LCD_CS_N, LCD_DC, LCD_RST_N, LCD_BL,

    // ESP32 UART link
    ESP_TXD, ESP_RXD, ESP_RTS_N, ESP_CTS_N,

    // debug output
    wb_debug
 );
 
    // ------------------------------------------------------------
    // Board IO parameters (customize for the FPGA target board
    // **These are for the Digilent NexysA7 (Nexys4 DDR)**
    // ------------------------------------------------------------
    localparam int 		NUM_LEDS = 16;
    localparam int 		NUM_SWITCHES = 16;
    localparam int 		NUM_BTNS = 5;
    localparam int 		NUM_RGBLEDS = 2;
    localparam bit[31:0]	BOARD_ID = "nxa7";
    
    // ------------------------------------------------------------
    // port declarations for module.  I used non-ANSI port assignments
    // to make use of localparams for the port sizing
    // ------------------------------------------------------------
    // system clock and reset
    input  logic	i_clk;
    input  logic	i_reset;

    // Wishbone master interface (from axil2wbsp)
    input  logic         i_wb_cyc;
    input  logic         i_wb_stb;
    input  logic         i_wb_we;
    input  logic [31:0]  i_wb_addr;
    input  logic [31:0]  i_wb_data;
    input  logic [3:0]   i_wb_sel;  
    output logic         o_wb_ack;
    output logic [31:0]  o_wb_data;

    // (Optional) interrupt outputs
    output logic o_irq0;
    output logic o_irq1;
    output logic o_irq2;

    // parameterized switches, buttons, leds, RGB LEDS
    input logic [NUM_BTNS-1:0]		btns;
    input logic [NUM_SWITCHES-1:0]	sw;
    output logic [NUM_LEDS-1:0]		leds;
    output logic [2:0]			rgb1RGB;
    output logic [2:0]			rgb2RGB;
    
    // 7-segment display controller outputs
    output logic [7:0]  AN;
    output logic        DP;
    output logic [6:0]  Digits_Bits;

    // ST7796S LCD outputs
    output logic LCD_SCLK;		// SPI clock (mode 0)
    output logic LCD_MOSI;		// SPI data to panel
    output logic LCD_CS_N;		// chip select (asserted low)
    output logic LCD_DC;		// data/command# select
    output logic LCD_RST_N;		// panel reset (asserted low)
    output logic LCD_BL;		// backlight enable

    // ESP32 UART link (names from the FPGA's point of view)
    output logic ESP_TXD;		// FPGA -> ESP32 RX
    input  logic ESP_RXD;		// ESP32 TX -> FPGA
    output logic ESP_RTS_N;		// FPGA -> ESP32 CTS (low = FPGA can accept data)
    input  logic ESP_CTS_N;		// ESP32 RTS -> FPGA (low = ESP32 can accept data)

    // debug outputs
    output logic [31:0] wb_debug;
	
    // ------------------------------------------------------------
    // Wires for peripheral interfaces
    // ------------------------------------------------------------
    logic o_boardio_cyc, o_boardio_stb, o_boardio_we;
    logic i_boardio_ack;
    logic [3:0] o_boardio_sel;
    logic [31:0] o_boardio_addr, o_boardio_data;
    logic [31:0] i_boardio_data;
    logic	 boardio_irq;	// interrupt when any of switches or buttons change
    
    logic o_sevenseg_cyc, o_sevenseg_stb, o_sevenseg_we;
    logic i_sevenseg_ack;
    logic [3:0] o_sevenseg_sel;
    logic [31:0] o_sevenseg_addr, o_sevenseg_data;
    logic [31:0] i_sevenseg_data;
    
    logic o_err_cyc, o_err_stb, o_err_we;
    logic i_err_ack;
    logic [3:0] o_err_sel;
    logic [31:0] o_err_addr, o_err_data;
    logic [31:0] i_err_data;

    logic o_lcd_cyc, o_lcd_stb, o_lcd_we;
    logic i_lcd_ack;
    logic [3:0] o_lcd_sel;
    logic [31:0] o_lcd_addr, o_lcd_data;
    logic [31:0] i_lcd_data;
    logic	 lcd_irq;	// asserted while the LCD interface is idle (if enabled)

    logic o_esp_cyc, o_esp_stb, o_esp_we;
    logic i_esp_ack;
    logic [3:0] o_esp_sel;
    logic [31:0] o_esp_addr, o_esp_data;
    logic [31:0] i_esp_data;
    logic	 esp_irq;	// RX threshold/timeout or TX low-water (if enabled)

    // ------------------------------------------------------------
    // RGB LED port mapping
    // ------------------------------------------------------------
    logic [NUM_RGBLEDS-1:0][2:0] rgb;
    assign rgb1RGB = rgb[0];
    assign rgb2RGB = rgb[1];
    
    // ------------------------------------------------------------
    // Instantiate Reset synchronizers
    // ------------------------------------------------------------
    logic sysrst;	// synchronized system (WB) reset signal

    sync_reset u_sys_sync_reset (
   	 .clk    (i_clk),
	 .arst   (i_reset),
	 .srst   (sysrst)
	);
    
    // ------------------------------------------------------------
    // Instantiate Wishbone Mux
    // ------------------------------------------------------------
    wb_mux u_mux (
        .i_clk(i_clk),
        .i_reset(sysrst),

        .i_wb_cyc(i_wb_cyc),
        .i_wb_stb(i_wb_stb),
        .i_wb_we(i_wb_we),
        .i_wb_addr(i_wb_addr),
        .i_wb_data(i_wb_data),
        .i_wb_sel(i_wb_sel),

        // Device 0: Parameterized Board IO - customizable by board type
        .o_s0_cyc(o_boardio_cyc),
        .o_s0_stb(o_boardio_stb),
        .o_s0_we(o_boardio_we),
        .o_s0_addr(o_boardio_addr),
        .o_s0_data(o_boardio_data),
        .o_s0_sel(o_boardio_sel),
        .i_s0_ack(i_boardio_ack),
        .i_s0_data(i_boardio_data),

        // Device 1: 7-segment display controller
        .o_s1_cyc(o_sevenseg_cyc),
        .o_s1_stb(o_sevenseg_stb),
        .o_s1_we(o_sevenseg_we),
        .o_s1_addr(o_sevenseg_addr),
        .o_s1_data(o_sevenseg_data),
        .o_s1_sel(o_sevenseg_sel),
        .i_s1_ack(i_sevenseg_ack),
        .i_s1_data(i_sevenseg_data),

        // Device 2: Error slave - responds if no other peripheral in wb_subsystem responds
        .o_err_cyc(o_err_cyc),
        .o_err_stb(o_err_stb),
        .o_err_we(o_err_we),
        .o_err_addr(o_err_addr),
        .o_err_data(o_err_data),
        .o_err_sel(o_err_sel),
        .i_err_ack(i_err_ack),
        .i_err_data(i_err_data),

	// Device 3: ST7796S SPI LCD controller
	.o_s3_cyc(o_lcd_cyc),
	.o_s3_stb(o_lcd_stb),
	.o_s3_we(o_lcd_we),
	.o_s3_addr(o_lcd_addr),
	.o_s3_data(o_lcd_data),
	.o_s3_sel(o_lcd_sel),
	.i_s3_ack(i_lcd_ack),
	.i_s3_data(i_lcd_data),

	// Device 4: ESP32 UART link
	.o_s4_cyc(o_esp_cyc),
	.o_s4_stb(o_esp_stb),
	.o_s4_we(o_esp_we),
	.o_s4_addr(o_esp_addr),
	.o_s4_data(o_esp_data),
	.o_s4_sel(o_esp_sel),
	.i_s4_ack(i_esp_ack),
	.i_s4_data(i_esp_data),

        // Mux output
        .o_wb_ack(o_wb_ack),
        .o_wb_data(o_wb_data)
    );

    // ------------------------------------------------------------
    //Paramterized Board I/O Peripheral (Device 2'b00)
    // ------------------------------------------------------------
    wb_boardio #(
        .DW(32),
        .AW(32),
        
        .NUM_LEDS(NUM_LEDS),
        .NUM_SWITCHES(NUM_SWITCHES),
        .NUM_BTNS(NUM_BTNS),
        .NUM_RGBLEDS(NUM_RGBLEDS),
        .BOARD_ID(BOARD_ID)     
    ) u_wb_boardio (
        .i_clk(i_clk),
        .i_reset(sysrst),

        .i_wb_cyc(o_boardio_cyc),
        .i_wb_stb(o_boardio_stb),
        .i_wb_we(o_boardio_we),
        .i_wb_addr(o_boardio_addr),
        .i_wb_data(o_boardio_data),
        .i_wb_sel(o_boardio_sel),
        .o_wb_ack(i_boardio_ack),
        .o_wb_data(i_boardio_data),

	// Board I/O
	.sw(sw),
	.btns(btns),
	.leds(leds),
	.rgb(rgb),
        
        // Interrupt output
        .irq_boardio(boardio_irq)
    );

    // ------------------------------------------------------------
    // Seven-segment Wishbone Peripheral (Device 2'b01)
    // ------------------------------------------------------------
    wb_sevenseg u_7seg (
        .i_clk(i_clk),
        .i_reset(i_reset),

        .i_wb_cyc(o_sevenseg_cyc),
        .i_wb_stb(o_sevenseg_stb),
        .i_wb_we(o_sevenseg_we),
        .i_wb_addr(o_sevenseg_addr),
        .i_wb_data(o_sevenseg_data),
        .i_wb_sel(o_sevenseg_sel),

        .o_wb_ack(i_sevenseg_ack),
        .o_wb_data(i_sevenseg_data),

        .AN(AN),
        .DP(DP),
        .Digits_Bits(Digits_Bits)
    );

    // ------------------------------------------------------------
    // Error Device (Device 2'b10)
    // ------------------------------------------------------------ 
    wb_err #(
    	.DW(32),
    	.AW(32)
    ) u_wb_err (
	.i_clk(i_clk),
	.i_reset(sysrst),

	.i_wb_cyc(o_err_cyc),
	.i_wb_stb(o_err_stb),
	.i_wb_we(o_err_we),
	.i_wb_addr(o_err_addr),
	.i_wb_data(o_err_data),
	.i_wb_sel(o_err_sel),

	.o_wb_ack(i_err_ack),
	.o_wb_data(i_err_data)
    );

    // ------------------------------------------------------------
    // ST7796S SPI LCD controller (Device 2'b11) - replaces wb_vga
    // ------------------------------------------------------------
    wb_lcd #(
	.FIFO_LG(9)		// 512-entry transmit FIFO (one RAMB18)
    ) u_lcd (
	.i_clk(i_clk),
	.i_reset(sysrst),

	.i_wb_cyc(o_lcd_cyc),
	.i_wb_stb(o_lcd_stb),
	.i_wb_we(o_lcd_we),
	.i_wb_addr(o_lcd_addr),
	.i_wb_data(o_lcd_data),
	.i_wb_sel(o_lcd_sel),

	.o_wb_data(i_lcd_data),
	.o_wb_ack(i_lcd_ack),

	.LCD_SCLK(LCD_SCLK),
	.LCD_MOSI(LCD_MOSI),
	.LCD_CS_N(LCD_CS_N),
	.LCD_DC(LCD_DC),
	.LCD_RST_N(LCD_RST_N),
	.LCD_BL(LCD_BL),

	.o_irq(lcd_irq)
    );

    // ------------------------------------------------------------
    // ESP32 UART link (Device 3'b100)
    // ------------------------------------------------------------
    wb_esp #(
	.RX_LG(12),		// 4 KB RX FIFO (one RAMB36)
	.TX_LG(10),		// 1 KB TX FIFO (one RAMB18)
	.RTS_MARGIN(32)
    ) u_esp (
	.i_clk(i_clk),
	.i_reset(sysrst),

	.i_wb_cyc(o_esp_cyc),
	.i_wb_stb(o_esp_stb),
	.i_wb_we(o_esp_we),
	.i_wb_addr(o_esp_addr),
	.i_wb_data(o_esp_data),
	.i_wb_sel(o_esp_sel),

	.o_wb_data(i_esp_data),
	.o_wb_ack(i_esp_ack),

	.ESP_TXD(ESP_TXD),
	.ESP_RXD(ESP_RXD),
	.ESP_RTS_N(ESP_RTS_N),
	.ESP_CTS_N(ESP_CTS_N),

	.o_irq(esp_irq)
    );

    // IRQs
    assign o_irq0 = boardio_irq;
    assign o_irq1 = lcd_irq;
    assign o_irq2 = esp_irq;

endmodule: wb_subsystem

