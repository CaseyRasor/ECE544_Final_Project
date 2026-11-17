/**
 * @file	wb_esp.sv
 * @brief	Wishbone UART peripheral for an ESP32 Wi-Fi co-processor link
 *
 * @date	17-Nov-2026
 * @version	1.0
 *
 * @detail
 * A UART (8N1) with deep block-RAM FIFOs and RTS/CTS hardware flow control,
 * intended to carry a packet protocol between the MicroBlaze and an ESP32.
 * The hardware is a plain byte pipe: framing, CRC, and message types are
 * handled in software.
 *
 *   - RX: bytes from the ESP32 land in the RX FIFO.  With flow control on,
 *     ESP_RTS_N is deasserted (high) when the RX FIFO has RTS_MARGIN or fewer
 *     free entries, so the ESP32 pauses before the FIFO can overflow.
 *   - TX: bytes written by software go to the TX FIFO and are sent when the
 *     ESP32 asserts ESP_CTS_N (low), or at once if flow control is off.
 *   - RX interrupt when the RX FIFO reaches RXTHRESH bytes, or when it holds
 *     data and the line has been idle for RXTIMEOUT bit times (end of a
 *     message shorter than the threshold).  TX interrupt when the TX FIFO
 *     level is <= TXTHRESH.
 *   - LOOPBACK connects the transmitter to the receiver internally (ESP_TXD
 *     idles high, CTS is ignored) for self-test without an ESP32.
 *
 * Byte map (offsets from the peripheral base, 32-bit accesses only):
 *   0x00 ESP_CTRL      RW  [0] RX_IRQ_EN
 *                          [1] TX_IRQ_EN
 *                          [2] FLOW_EN    RTS/CTS flow control      (reset 0)
 *                          [3] LOOPBACK   internal TX->RX loopback
 *                          [4] RX_FLUSH   write 1 to empty the RX FIFO (self-clearing)
 *                          [5] TX_FLUSH   write 1 to empty the TX FIFO (self-clearing;
 *                                         a character already on the wire finishes)
 *   0x04 ESP_STATUS    RO  [0] RX_AVAIL   RX FIFO not empty
 *                          [1] RX_FULL
 *                          [2] TX_EMPTY   TX FIFO empty
 *                          [3] TX_FULL
 *                          [4] TX_IDLE    TX FIFO empty and nothing being sent
 *                          [5] RX_BUSY    a character is being received
 *                          [6] RX_TIMEOUT RX idle timeout reached
 *                          [7] IRQ        state of o_irq
 *                          [8] RX_IRQ     RX interrupt condition (before enable)
 *                          [9] TX_IRQ     TX interrupt condition (before enable)
 *                      W1C [16] OVERRUN   byte received with RX FIFO full (dropped)
 *                      W1C [17] FRAME_ERR stop bit was 0 (byte dropped)
 *                      W1C [18] UNDERRUN  ESP_RXDATA32 read with fewer than 4 bytes
 *                          [24] CTS       1 = ESP32 is ready to receive (ESP_CTS_N low)
 *                          [25] RTS       1 = FPGA is ready to receive  (ESP_RTS_N low)
 *                      Writing 1 to a W1C bit clears it; other bits ignore writes.
 *   0x08 ESP_BAUDDIV   RW  [15:0] clocks per bit = 100 MHz / baud   (reset 868 -> 115200)
 *                             values below 8 are stored as 8.  2 Mbaud = 50.
 *   0x0C ESP_LEVEL     RO  [15:0] bytes in RX FIFO, [31:16] bytes in TX FIFO
 *   0x10 ESP_RXTHRESH  RW  [15:0] RX IRQ when RX level >= this     (reset 1)
 *   0x14 ESP_RXTIMEOUT RW  [15:0] RX idle timeout in bit times, 0 = off (reset 40)
 *   0x18 ESP_TXTHRESH  RW  [15:0] TX IRQ when TX level <= this     (reset 0)
 *   0x1C (reserved)
 *   0x20 ESP_TXDATA    WO  [7:0]  queue one byte
 *   0x24 ESP_TXDATA32  WO  [31:0] queue four bytes, [7:0] sent first
 *   0x28 ESP_RXDATA    RO  read one byte: [7:0] data, [31] = 1 if the FIFO was
 *                          empty (nothing removed)
 *   0x2C ESP_RXDATA32  RO  read four bytes, first received in [7:0].  Only read
 *                          when ESP_LEVEL shows >= 4 bytes; otherwise returns 0,
 *                          removes nothing, and sets UNDERRUN.
 *   0x30 ESP_ID        RO  32'h4553_3332 ("ES32")
 *   0x34 ESP_FIFOSZ    RO  [15:0] RX FIFO depth, [31:16] TX FIFO depth
 *
 * Bus notes:
 *   - Same bus assumptions as wb_lcd: the request is captured on the one-cycle
 *     STB, and only one transaction is outstanding.
 *   - A write to TXDATA/TXDATA32 holds ACK until all its bytes are in the TX
 *     FIFO, so a full FIFO stalls the CPU instead of losing data.  Software
 *     that must not block can check ESP_LEVEL first.
 *   - RXDATA reads take ~3 cycles and RXDATA32 reads ~6 cycles to ACK.
 *   - Writes ignore i_wb_sel; use 32-bit accesses (Xil_Out32 / Xil_In32).
 */
 // SPDX-License-Identifier: MIT

`default_nettype wire

module wb_esp #(
    parameter int          RX_LG       = 12,		// RX FIFO depth = 2**RX_LG bytes (4096)
    parameter int          TX_LG       = 10,		// TX FIFO depth = 2**TX_LG bytes (1024)
    parameter int          RTS_MARGIN  = 32,		// deassert RTS at <= this many free bytes
    parameter logic [15:0] DEFAULT_DIV = 16'd868	// 115200 baud at 100 MHz
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

    // ESP32 UART pins (names from the FPGA's point of view)
    output logic        ESP_TXD,	// FPGA -> ESP32 RX
    input  logic        ESP_RXD,	// ESP32 TX -> FPGA
    output logic        ESP_RTS_N,	// FPGA -> ESP32 CTS  (low = FPGA can accept data)
    input  logic        ESP_CTS_N,	// ESP32 RTS -> FPGA  (low = ESP32 can accept data)

    // interrupt (level, active high)
    output logic        o_irq
);

    //--------------------------------------------------------------------------
    // Register map (local word addresses = byte offset >> 2)
    //--------------------------------------------------------------------------
    localparam logic [13:0] REG_CTRL      = 14'h0000;
    localparam logic [13:0] REG_STATUS    = 14'h0001;
    localparam logic [13:0] REG_BAUDDIV   = 14'h0002;
    localparam logic [13:0] REG_LEVEL     = 14'h0003;
    localparam logic [13:0] REG_RXTHRESH  = 14'h0004;
    localparam logic [13:0] REG_RXTIMEOUT = 14'h0005;
    localparam logic [13:0] REG_TXTHRESH  = 14'h0006;
    localparam logic [13:0] REG_TXDATA    = 14'h0008;
    localparam logic [13:0] REG_TXDATA32  = 14'h0009;
    localparam logic [13:0] REG_RXDATA    = 14'h000A;
    localparam logic [13:0] REG_RXDATA32  = 14'h000B;
    localparam logic [13:0] REG_ID        = 14'h000C;
    localparam logic [13:0] REG_FIFOSZ    = 14'h000D;

    localparam logic [31:0] ESP_ID_VALUE  = 32'h4553_3332;	// "ES32"
    localparam logic [15:0] MIN_DIV       = 16'd8;

    localparam int RX_DEPTH = 1 << RX_LG;
    localparam int TX_DEPTH = 1 << TX_LG;

    //--------------------------------------------------------------------------
    // Signals
    //--------------------------------------------------------------------------
    logic [13:0] local_word_addr;
    logic        wb_access;
    logic        bus_busy;

    // control / config registers
    logic        ctrl_rx_irq_en;
    logic        ctrl_tx_irq_en;
    logic        ctrl_flow_en;
    logic        ctrl_loopback;
    logic        rx_flush;			// one-cycle pulses
    logic        tx_flush;
    logic [15:0] baud_div;
    logic [15:0] rx_thresh;
    logic [15:0] rx_timeout_bits;
    logic [15:0] tx_thresh;

    // sticky error flags
    logic        err_overrun;
    logic        err_frame;
    logic        err_underrun;

    // pin synchronizers
    (* ASYNC_REG = "TRUE" *) logic [1:0] rxd_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] cts_sync;
    logic        rxd_s;
    logic        cts_n_s;

    // UART cores
    logic        tx_line;
    logic        tx_busy;
    logic        tx_start;
    logic        rx_in;
    logic        rx_valid;
    logic [7:0]  rx_byte;
    logic        rx_frame_err;
    logic        rx_busy;

    // TX FIFO
    logic        tx_wr, tx_rd, tx_full, tx_empty;
    logic [7:0]  tx_din, tx_dout;
    logic [TX_LG:0] tx_level;
    logic        tx_fetch;			// a byte was popped; start it next cycle
    logic        cts_ok;

    // RX FIFO
    logic        rx_rd, rx_full, rx_empty;
    logic [7:0]  rx_dout;
    logic [RX_LG:0] rx_level;
    logic [RX_LG:0] rx_free;

    // bus write -> TX FIFO sequencer
    logic [2:0]  wpend_cnt;			// bytes still to push
    logic [31:0] wpend_word;

    // bus read <- RX FIFO sequencer
    logic [2:0]  pop_left;			// pops still to issue
    logic [2:0]  cap_left;			// bytes still to capture
    logic [1:0]  cap_idx;
    logic        cap_valid;			// rx_dout holds a popped byte this cycle
    logic [31:0] rd_word;
    logic [31:0] rd_word_next;

    // RX idle timeout
    logic [15:0] tick_cnt;
    logic        bit_tick;
    logic [15:0] idle_bits;
    logic        rx_timeout;

    // interrupts
    logic        rx_irq;
    logic        tx_irq;
    logic        tx_idle;

    //--------------------------------------------------------------------------
    // Pin synchronizers (idle/inactive = high)
    //--------------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            rxd_sync <= 2'b11;
            cts_sync <= 2'b11;
        end
        else begin
            rxd_sync <= {rxd_sync[0], ESP_RXD};
            cts_sync <= {cts_sync[0], ESP_CTS_N};
        end
    end

    assign rxd_s   = rxd_sync[1];
    assign cts_n_s = cts_sync[1];

    //--------------------------------------------------------------------------
    // Address decode
    //--------------------------------------------------------------------------
    assign local_word_addr = i_wb_addr[15:2];
    assign wb_access       = i_wb_cyc && i_wb_stb;
    assign bus_busy        = (wpend_cnt != 0) || (pop_left != 0) || (cap_left != 0);

    //--------------------------------------------------------------------------
    // FIFO data paths driven by the bus sequencers
    //--------------------------------------------------------------------------
    assign tx_wr  = (wpend_cnt != 0) && !tx_full;
    assign tx_din = wpend_word[7:0];

    assign rx_rd  = (pop_left != 0);	// count is guaranteed: only this logic pops

    always_comb begin
        rd_word_next = rd_word;
        rd_word_next[8*cap_idx +: 8] = rx_dout;
    end

    //--------------------------------------------------------------------------
    // Wishbone register logic
    //--------------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            o_wb_ack        <= 1'b0;
            o_wb_data       <= 32'h0;
            ctrl_rx_irq_en  <= 1'b0;
            ctrl_tx_irq_en  <= 1'b0;
            ctrl_flow_en    <= 1'b0;
            ctrl_loopback   <= 1'b0;
            rx_flush        <= 1'b0;
            tx_flush        <= 1'b0;
            baud_div        <= DEFAULT_DIV;
            rx_thresh       <= 16'd1;
            rx_timeout_bits <= 16'd40;
            tx_thresh       <= 16'd0;
            err_overrun     <= 1'b0;
            err_frame       <= 1'b0;
            err_underrun    <= 1'b0;
            wpend_cnt       <= '0;
            wpend_word      <= '0;
            pop_left        <= '0;
            cap_left        <= '0;
            cap_idx         <= '0;
            cap_valid       <= 1'b0;
            rd_word         <= '0;
        end
        else begin
            o_wb_ack  <= 1'b0;
            rx_flush  <= 1'b0;
            tx_flush  <= 1'b0;
            cap_valid <= rx_rd;

            // ---- write sequencer: one byte per cycle into the TX FIFO ----
            if (tx_wr) begin
                wpend_word <= {8'h00, wpend_word[31:8]};
                wpend_cnt  <= wpend_cnt - 3'd1;
                if (wpend_cnt == 3'd1)
                    o_wb_ack <= 1'b1;
            end

            // ---- read sequencer: pop, then capture one cycle later ----
            if (rx_rd)
                pop_left <= pop_left - 3'd1;

            if (cap_valid) begin
                rd_word  <= rd_word_next;
                cap_idx  <= cap_idx + 2'd1;
                cap_left <= cap_left - 3'd1;
                if (cap_left == 3'd1) begin
                    o_wb_ack  <= 1'b1;
                    o_wb_data <= rd_word_next;
                end
            end

            // ---- new bus request ----
            if (wb_access && !bus_busy) begin
                if (i_wb_we) begin
                    case (local_word_addr)
                        REG_TXDATA: begin
                            wpend_word <= {24'h0, i_wb_data[7:0]};
                            wpend_cnt  <= 3'd1;
                        end
                        REG_TXDATA32: begin
                            wpend_word <= i_wb_data;
                            wpend_cnt  <= 3'd4;
                        end
                        default: begin
                            o_wb_ack <= 1'b1;
                            case (local_word_addr)
                                REG_CTRL: begin
                                    ctrl_rx_irq_en <= i_wb_data[0];
                                    ctrl_tx_irq_en <= i_wb_data[1];
                                    ctrl_flow_en   <= i_wb_data[2];
                                    ctrl_loopback  <= i_wb_data[3];
                                    rx_flush       <= i_wb_data[4];
                                    tx_flush       <= i_wb_data[5];
                                end
                                REG_STATUS: begin
                                    if (i_wb_data[16]) err_overrun  <= 1'b0;
                                    if (i_wb_data[17]) err_frame    <= 1'b0;
                                    if (i_wb_data[18]) err_underrun <= 1'b0;
                                end
                                REG_BAUDDIV:   baud_div <= (i_wb_data[15:0] < MIN_DIV) ?
                                                           MIN_DIV : i_wb_data[15:0];
                                REG_RXTHRESH:  rx_thresh       <= i_wb_data[15:0];
                                REG_RXTIMEOUT: rx_timeout_bits <= i_wb_data[15:0];
                                REG_TXTHRESH:  tx_thresh       <= i_wb_data[15:0];
                                default: ;	// read-only or unmapped - ignore
                            endcase
                        end
                    endcase
                end
                else begin
                    case (local_word_addr)
                        REG_RXDATA: begin
                            if (rx_empty) begin
                                o_wb_ack  <= 1'b1;
                                o_wb_data <= 32'h8000_0000;
                            end
                            else begin
                                pop_left <= 3'd1;
                                cap_left <= 3'd1;
                                cap_idx  <= '0;
                                rd_word  <= '0;
                            end
                        end
                        REG_RXDATA32: begin
                            if (rx_level < 4) begin
                                o_wb_ack     <= 1'b1;
                                o_wb_data    <= 32'h0;
                                err_underrun <= 1'b1;
                            end
                            else begin
                                pop_left <= 3'd4;
                                cap_left <= 3'd4;
                                cap_idx  <= '0;
                                rd_word  <= '0;
                            end
                        end
                        default: begin
                            o_wb_ack <= 1'b1;
                            case (local_word_addr)
                                REG_CTRL:      o_wb_data <= {28'h0, ctrl_loopback, ctrl_flow_en,
                                                             ctrl_tx_irq_en, ctrl_rx_irq_en};
                                REG_STATUS:    o_wb_data <= {6'h0, !ESP_RTS_N, !cts_n_s,
                                                             5'h0, err_underrun, err_frame, err_overrun,
                                                             6'h0, tx_irq, rx_irq,
                                                             o_irq, rx_timeout, rx_busy, tx_idle,
                                                             tx_full, tx_empty, rx_full, !rx_empty};
                                REG_BAUDDIV:   o_wb_data <= {16'h0, baud_div};
                                REG_LEVEL:     o_wb_data <= {16'(tx_level), 16'(rx_level)};
                                REG_RXTHRESH:  o_wb_data <= {16'h0, rx_thresh};
                                REG_RXTIMEOUT: o_wb_data <= {16'h0, rx_timeout_bits};
                                REG_TXTHRESH:  o_wb_data <= {16'h0, tx_thresh};
                                REG_ID:        o_wb_data <= ESP_ID_VALUE;
                                REG_FIFOSZ:    o_wb_data <= {16'(TX_DEPTH), 16'(RX_DEPTH)};
                                default:       o_wb_data <= 32'h0;
                            endcase
                        end
                    endcase
                end
            end

            // ---- error flags (placed last so a new event wins over a clear) ----
            if (rx_valid && rx_full) err_overrun <= 1'b1;
            if (rx_frame_err)        err_frame   <= 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // FIFOs
    //--------------------------------------------------------------------------
    lcd_fifo #(
        .W  (8),
        .LG (TX_LG)
    ) u_tx_fifo (
        .i_clk   (i_clk),
        .i_rst   (i_reset),
        .i_clr   (tx_flush),
        .i_wr    (tx_wr),
        .i_din   (tx_din),
        .i_rd    (tx_rd),
        .o_dout  (tx_dout),
        .o_full  (tx_full),
        .o_empty (tx_empty),
        .o_level (tx_level)
    );

    lcd_fifo #(
        .W  (8),
        .LG (RX_LG)
    ) u_rx_fifo (
        .i_clk   (i_clk),
        .i_rst   (i_reset),
        .i_clr   (rx_flush),
        .i_wr    (rx_valid),		// dropped (and OVERRUN set) when full
        .i_din   (rx_byte),
        .i_rd    (rx_rd),
        .o_dout  (rx_dout),
        .o_full  (rx_full),
        .o_empty (rx_empty),
        .o_level (rx_level)
    );

    //--------------------------------------------------------------------------
    // Transmit path: FIFO -> UART TX, gated by CTS
    //--------------------------------------------------------------------------
    assign cts_ok   = !ctrl_flow_en || ctrl_loopback || !cts_n_s;
    assign tx_rd    = !tx_fetch && !tx_busy && !tx_empty && cts_ok;
    assign tx_start = tx_fetch;
    assign tx_idle  = tx_empty && !tx_busy && !tx_fetch && (wpend_cnt == 0);

    always_ff @(posedge i_clk) begin
        if (i_reset || tx_flush)
            tx_fetch <= 1'b0;
        else
            tx_fetch <= tx_rd;
    end

    esp_uart_tx u_uart_tx (
        .i_clk   (i_clk),
        .i_rst   (i_reset),
        .i_div   (baud_div),
        .i_start (tx_start),
        .i_data  (tx_dout),
        .o_tx    (tx_line),
        .o_busy  (tx_busy)
    );

    //--------------------------------------------------------------------------
    // Receive path: UART RX (or internal loopback) -> FIFO
    //--------------------------------------------------------------------------
    assign rx_in = ctrl_loopback ? tx_line : rxd_s;

    esp_uart_rx u_uart_rx (
        .i_clk       (i_clk),
        .i_rst       (i_reset),
        .i_div       (baud_div),
        .i_rx        (rx_in),
        .o_valid     (rx_valid),
        .o_data      (rx_byte),
        .o_frame_err (rx_frame_err),
        .o_busy      (rx_busy)
    );

    //--------------------------------------------------------------------------
    // RX idle timeout: counts bit times since the last activity while the RX
    // FIFO holds data.  Restarts on a received byte or a software read.
    //--------------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset || tick_cnt == 0)
            tick_cnt <= baud_div - 16'd1;
        else
            tick_cnt <= tick_cnt - 16'd1;
    end

    assign bit_tick = (tick_cnt == 0);

    always_ff @(posedge i_clk) begin
        if (i_reset || rx_flush || rx_busy || rx_valid || rx_rd || rx_empty)
            idle_bits <= '0;
        else if (bit_tick && idle_bits != 16'hFFFF)
            idle_bits <= idle_bits + 16'd1;
    end

    assign rx_timeout = (rx_timeout_bits != 0) && !rx_empty &&
                        (idle_bits >= rx_timeout_bits);

    //--------------------------------------------------------------------------
    // Flow control output and TX pin
    //--------------------------------------------------------------------------
    assign rx_free = (RX_LG+1)'(RX_DEPTH) - rx_level;

    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            ESP_RTS_N <= 1'b1;
            ESP_TXD   <= 1'b1;
        end
        else begin
            ESP_RTS_N <= ctrl_flow_en && (rx_free <= (RX_LG+1)'(RTS_MARGIN));
            ESP_TXD   <= ctrl_loopback ? 1'b1 : tx_line;
        end
    end

    //--------------------------------------------------------------------------
    // Interrupt
    //--------------------------------------------------------------------------
    assign rx_irq = !rx_empty && ((32'(rx_level) >= 32'(rx_thresh)) || rx_timeout);
    assign tx_irq = (32'(tx_level) <= 32'(tx_thresh));
    assign o_irq  = (ctrl_rx_irq_en && rx_irq) || (ctrl_tx_irq_en && tx_irq);

endmodule: wb_esp
