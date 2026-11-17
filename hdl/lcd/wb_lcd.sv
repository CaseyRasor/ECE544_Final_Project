/**
 * @file	wb_lcd.sv
 * @brief	Wishbone peripheral for an ST7796S SPI TFT LCD (320 x 480, RGB565)
 *
 * @date	16-Nov-2026
 * @version	1.0
 *
 * @detail
 * Replaces the wb_vga text-mode peripheral in the MBC_WB system.  The hardware
 * is a command/data FIFO + SPI shift engine; software is responsible for the
 * panel init sequence, address windowing (CASET/RASET), and drawing.
 *
 * Writing to one of the "push" registers (CMD, DATA8, DATA16, FILL) enqueues an
 * entry in the transmit FIFO.  If the FIFO is full the Wishbone ACK is withheld
 * until space is available, so software never loses data - but a long stall
 * also stalls the CPU.  Software that must not block can poll
 * LCD_STATUS.FIFO_FULL (or FIFO_LEVEL) before pushing.
 *
 * Byte map (offsets from the peripheral base, 32-bit accesses only):
 *   0x00 LCD_CTRL     RW  [0] RST       1 = drive LCD_RST_N low (panel in reset)  (reset value 1)
 *                         [1] BL        1 = backlight on                          (reset value 0)
 *                         [2] IRQ_EN    1 = assert IRQ while the interface is idle
 *                         [3] FLUSH     write 1 to empty the FIFO and abort the
 *                                       transfer in progress (self-clearing, reads 0)
 *   0x04 LCD_STATUS   RO  [0] BUSY      FIFO not empty or SPI transfer in progress
 *                         [1] FULL      FIFO full
 *                         [2] EMPTY     FIFO empty
 *                         [3] IRQ       IRQ output state (IRQ_EN & !BUSY)
 *                         [25:16] LEVEL number of entries in the FIFO
 *   0x08 LCD_CLKDIV   RW  [7:0]  SCLK = 100MHz / (2*(DIV+1))   (reset value 3 -> 12.5 MHz)
 *   0x0C LCD_FILLCNT  RW  [17:0] repeat count used by LCD_FILL  (reset value 1)
 *   0x10 LCD_CMD      WO  [7:0]  push command byte   (DC = 0)
 *   0x14 LCD_DATA8    WO  [7:0]  push data byte      (DC = 1)
 *   0x18 LCD_DATA16   WO  [15:0] push one pixel      (DC = 1, 16 bits, MSB first)
 *   0x1C LCD_FILL     WO  [15:0] push pixel repeated LCD_FILLCNT times (DC = 1)
 *   0x20 LCD_ID       RO  32'h3737_3936 ("7796")
 *   0x24 LCD_FIFOSZ   RO  FIFO depth in entries
 *
 * Bus notes:
 *   - The AXI-Lite -> Wishbone bridge is a pipelined master that holds STB for
 *     one cycle and then waits for ACK with CYC held.  The request is captured
 *     on the STB cycle.  Like the other MBC_WB peripherals this assumes only
 *     one outstanding transaction (true for MicroBlaze M_AXI_DP).
 *   - Writes ignore i_wb_sel; use 32-bit writes (Xil_Out32) from software.
 */
 // SPDX-License-Identifier: MIT

`default_nettype wire

module wb_lcd #(
    parameter int FIFO_LG = 9		// FIFO depth = 2**FIFO_LG entries (512)
) (
    input  logic        i_clk,
    input  logic        i_reset,

    // Wishbone slave interface
    input  logic        i_wb_cyc,
    input  logic        i_wb_stb,
    input  logic        i_wb_we,
    input  logic [31:0] i_wb_addr,	// byte address (low 16 bits used)
    input  logic [31:0] i_wb_data,
    input  logic [3:0]  i_wb_sel,

    output logic [31:0] o_wb_data,
    output logic        o_wb_ack,

    // LCD pins
    output logic        LCD_SCLK,
    output logic        LCD_MOSI,
    output logic        LCD_CS_N,
    output logic        LCD_DC,
    output logic        LCD_RST_N,
    output logic        LCD_BL,

    // interrupt (level, active high)
    output logic        o_irq
);

    //--------------------------------------------------------------------------
    // Register map (local word addresses = byte offset >> 2)
    //--------------------------------------------------------------------------
    localparam logic [13:0] REG_CTRL    = 14'h0000;
    localparam logic [13:0] REG_STATUS  = 14'h0001;
    localparam logic [13:0] REG_CLKDIV  = 14'h0002;
    localparam logic [13:0] REG_FILLCNT = 14'h0003;
    localparam logic [13:0] REG_CMD     = 14'h0004;
    localparam logic [13:0] REG_DATA8   = 14'h0005;
    localparam logic [13:0] REG_DATA16  = 14'h0006;
    localparam logic [13:0] REG_FILL    = 14'h0007;
    localparam logic [13:0] REG_ID      = 14'h0008;
    localparam logic [13:0] REG_FIFOSZ  = 14'h0009;

    localparam logic [31:0] LCD_ID_VALUE = 32'h3737_3936;	// "7796"

    localparam logic [1:0] T_CMD   = 2'b00;
    localparam logic [1:0] T_DATA8 = 2'b01;
    localparam logic [1:0] T_PIXEL = 2'b10;

    //--------------------------------------------------------------------------
    // Signals
    //--------------------------------------------------------------------------
    logic [13:0] local_word_addr;
    logic        wb_access;
    logic        is_push_reg;

    // control registers
    logic        ctrl_rst;
    logic        ctrl_bl;
    logic        ctrl_irq_en;
    logic        flush;			// one-cycle pulse
    logic [7:0]  clkdiv;
    logic [17:0] fill_cnt;

    // pending push (FIFO was full when the write arrived)
    logic        pend;
    logic [35:0] pend_entry;

    // FIFO
    logic        fifo_wr;
    logic [35:0] fifo_din;
    logic        fifo_rd;
    logic [35:0] fifo_dout;
    logic        fifo_full;
    logic        fifo_empty;
    logic [FIFO_LG:0] fifo_level;

    // engine
    logic        eng_busy;
    logic        busy;

    //--------------------------------------------------------------------------
    // Address decode and push-entry formation
    //--------------------------------------------------------------------------
    assign local_word_addr = i_wb_addr[15:2];
    assign wb_access       = i_wb_cyc && i_wb_stb;

    assign is_push_reg = (local_word_addr == REG_CMD)    ||
                         (local_word_addr == REG_DATA8)  ||
                         (local_word_addr == REG_DATA16) ||
                         (local_word_addr == REG_FILL);

    // FIFO entry that the current bus write would push
    logic [35:0] bus_entry;
    always_comb begin
        case (local_word_addr)
            REG_CMD:    bus_entry = {T_CMD,   18'd1,    8'h00, i_wb_data[7:0]};
            REG_DATA8:  bus_entry = {T_DATA8, 18'd1,    8'h00, i_wb_data[7:0]};
            REG_DATA16: bus_entry = {T_PIXEL, 18'd1,    i_wb_data[15:0]};
            default:    bus_entry = {T_PIXEL, fill_cnt, i_wb_data[15:0]};	// REG_FILL
        endcase
    end

    // Push is combinational so FIFO occupancy is always exact.
    // A pending entry has priority; no new request can arrive while one is
    // pending because its ACK has not been given yet.
    logic new_push;
    assign new_push = wb_access && i_wb_we && is_push_reg && !pend;

    always_comb begin
        fifo_wr  = 1'b0;
        fifo_din = bus_entry;
        if (pend) begin
            fifo_wr  = !fifo_full;
            fifo_din = pend_entry;
        end
        else if (new_push) begin
            fifo_wr  = !fifo_full;
        end
    end

    //--------------------------------------------------------------------------
    // Wishbone register logic
    //--------------------------------------------------------------------------
    assign busy = eng_busy || !fifo_empty;

    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            o_wb_ack    <= 1'b0;
            o_wb_data   <= 32'h0;
            ctrl_rst    <= 1'b1;
            ctrl_bl     <= 1'b0;
            ctrl_irq_en <= 1'b0;
            flush       <= 1'b0;
            clkdiv      <= 8'd3;
            fill_cnt    <= 18'd1;
            pend        <= 1'b0;
            pend_entry  <= '0;
        end
        else begin
            o_wb_ack <= 1'b0;
            flush    <= 1'b0;

            if (pend) begin
                // waiting for FIFO space for a previously captured push
                if (!fifo_full) begin
                    pend     <= 1'b0;
                    o_wb_ack <= 1'b1;
                end
            end
            else if (wb_access) begin
                o_wb_data <= 32'h0;

                if (i_wb_we) begin
                    if (is_push_reg) begin
                        if (fifo_full) begin
                            pend       <= 1'b1;	// hold ACK until pushed
                            pend_entry <= bus_entry;
                        end
                        else begin
                            o_wb_ack <= 1'b1;
                        end
                    end
                    else begin
                        o_wb_ack <= 1'b1;
                        case (local_word_addr)
                            REG_CTRL: begin
                                ctrl_rst    <= i_wb_data[0];
                                ctrl_bl     <= i_wb_data[1];
                                ctrl_irq_en <= i_wb_data[2];
                                flush       <= i_wb_data[3];
                            end
                            REG_CLKDIV:  clkdiv   <= i_wb_data[7:0];
                            REG_FILLCNT: fill_cnt <= i_wb_data[17:0];
                            default: ;	// read-only or unmapped - ignore
                        endcase
                    end
                end
                else begin
                    o_wb_ack <= 1'b1;
                    case (local_word_addr)
                        REG_CTRL:    o_wb_data <= {29'h0, ctrl_irq_en, ctrl_bl, ctrl_rst};
                        REG_STATUS:  o_wb_data <= {6'h0, 10'(fifo_level), 12'h0,
                                                   o_irq, fifo_empty, fifo_full, busy};
                        REG_CLKDIV:  o_wb_data <= {24'h0, clkdiv};
                        REG_FILLCNT: o_wb_data <= {14'h0, fill_cnt};
                        REG_ID:      o_wb_data <= LCD_ID_VALUE;
                        REG_FIFOSZ:  o_wb_data <= 32'(1 << FIFO_LG);
                        default:     o_wb_data <= 32'h0;
                    endcase
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Transmit FIFO
    //--------------------------------------------------------------------------
    lcd_fifo #(
        .W  (36),
        .LG (FIFO_LG)
    ) u_lcd_fifo (
        .i_clk   (i_clk),
        .i_rst   (i_reset),
        .i_clr   (flush),
        .i_wr    (fifo_wr),
        .i_din   (fifo_din),
        .i_rd    (fifo_rd),
        .o_dout  (fifo_dout),
        .o_full  (fifo_full),
        .o_empty (fifo_empty),
        .o_level (fifo_level)
    );

    //--------------------------------------------------------------------------
    // SPI engine
    //--------------------------------------------------------------------------
    lcd_spi_engine u_lcd_spi_engine (
        .i_clk        (i_clk),
        .i_rst        (i_reset),
        .i_abort      (flush),
        .i_clkdiv     (clkdiv),
        .i_fifo_empty (fifo_empty),
        .o_fifo_rd    (fifo_rd),
        .i_fifo_dout  (fifo_dout),
        .o_sclk       (LCD_SCLK),
        .o_mosi       (LCD_MOSI),
        .o_cs_n       (LCD_CS_N),
        .o_dc         (LCD_DC),
        .o_busy       (eng_busy)
    );

    //--------------------------------------------------------------------------
    // Outputs
    //--------------------------------------------------------------------------
    assign LCD_RST_N = ~ctrl_rst;
    assign LCD_BL    = ctrl_bl;
    assign o_irq     = ctrl_irq_en && !busy;

endmodule: wb_lcd
