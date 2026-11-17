/**
 * @file	lcd_spi_engine.sv
 * @brief	SPI transmit engine for an ST7796S (4-wire serial, write-only)
 *
 * @date	16-Nov-2026
 * @version	1.0
 *
 * @detail
 * Pops entries from the LCD transmit FIFO and shifts them out using SPI mode 0
 * (SCLK idles low, panel samples MOSI on the rising edge, MSB first).
 *
 * FIFO entry format (36 bits):
 *   [35:34] type   : 2'b00 = CMD   (8 bits,  DC = 0)
 *                    2'b01 = DATA8 (8 bits,  DC = 1)
 *                    2'b10 = PIXEL (16 bits, DC = 1), sent COUNT times
 *                    2'b11 = reserved (treated as PIXEL)
 *   [33:16] count  : number of times the word is sent (0 = entry is skipped).
 *                    CMD/DATA8 entries are always pushed with count = 1.
 *   [15:0]  data   : CMD/DATA8 use [7:0]; PIXEL uses [15:0] (RGB565)
 *
 * SCLK frequency = f(i_clk) / (2 * (i_clkdiv + 1))
 *   100 MHz sysclk: clkdiv = 0 -> 50 MHz, 1 -> 25 MHz, 3 -> 12.5 MHz, 4 -> 10 MHz
 *   (ST7796S datasheet serial write cycle min is 66 ns (~15 MHz); many modules
 *    run reliably faster, but start slow when bringing up hardware.)
 *
 * CS# is asserted before the first SCLK edge and held low for as long as the
 * FIFO keeps supplying entries, so a whole RAMWR burst goes out under a single
 * CS# assertion.  When the FIFO runs dry CS# is held for one half-period after
 * the last falling SCLK edge, then released for at least one half-period
 * before it can be asserted again.  DC changes only while SCLK is low and at
 * least one half-period before the next rising edge.
 */
 // SPDX-License-Identifier: MIT

`default_nettype wire

module lcd_spi_engine (
    input  logic        i_clk,
    input  logic        i_rst,
    input  logic        i_abort,	// synchronous abort (used w/ FIFO flush)

    input  logic [7:0]  i_clkdiv,	// half-period = i_clkdiv + 1 clocks

    // FIFO read interface (registered-read FIFO)
    input  logic        i_fifo_empty,
    output logic        o_fifo_rd,
    input  logic [35:0] i_fifo_dout,

    // serial interface
    output logic        o_sclk,
    output logic        o_mosi,
    output logic        o_cs_n,
    output logic        o_dc,

    // status
    output logic        o_busy		// asserted while a transfer is in progress
);

    localparam logic [1:0] T_CMD   = 2'b00;
    localparam logic [1:0] T_DATA8 = 2'b01;

    typedef enum logic [2:0] {
        S_IDLE,		// CS# high, waiting for FIFO data
        S_FETCH,	// pop requested from FIFO
        S_LOAD,		// FIFO data valid - load shifter
        S_SHIFT,	// clocking bits out
        S_NEXT,		// word finished - fetch next or wind down
        S_CSHOLD,	// hold CS# low half-period after last SCLK edge
        S_CSGAP		// hold CS# high half-period before next transfer
    } state_t;

    state_t state;

    logic [7:0]  div_cnt;
    logic        tick;			// one half-period has elapsed

    logic [15:0] shreg;
    logic [3:0]  bit_cnt;		// bits remaining - 1
    logic [15:0] word;			// saved word for PIXEL repeats
    logic        is_pixel;
    logic [17:0] rep_left;		// words remaining including current one

    // fields of the entry presented by the FIFO
    logic [1:0]  f_type;
    logic [17:0] f_count;
    logic [15:0] f_data;
    assign f_type  = i_fifo_dout[35:34];
    assign f_count = i_fifo_dout[33:16];
    assign f_data  = i_fifo_dout[15:0];

    assign tick   = (div_cnt == i_clkdiv);
    assign o_mosi = shreg[15];
    assign o_busy = (state != S_IDLE);

    // FIFO pop is combinational so the entry is valid in S_LOAD
    always_comb begin
        o_fifo_rd = 1'b0;
        if (!i_abort) begin
            if ((state == S_IDLE) && !i_fifo_empty)
                o_fifo_rd = 1'b1;
            else if ((state == S_NEXT) && !i_fifo_empty)
                o_fifo_rd = 1'b1;
        end
    end

    always_ff @(posedge i_clk) begin
        if (i_rst || i_abort) begin
            state    <= S_IDLE;
            div_cnt  <= '0;
            o_sclk   <= 1'b0;
            o_cs_n   <= 1'b1;
            o_dc     <= 1'b1;
            shreg    <= '0;
            bit_cnt  <= '0;
            word     <= '0;
            is_pixel <= 1'b0;
            rep_left <= '0;
        end
        else begin
            // half-period timer: free-runs in the states that need it
            if ((state == S_SHIFT) || (state == S_CSHOLD) || (state == S_CSGAP))
                div_cnt <= tick ? 8'd0 : div_cnt + 8'd1;
            else
                div_cnt <= 8'd0;

            case (state)
                S_IDLE: begin
                    o_sclk <= 1'b0;
                    if (!i_fifo_empty)
                        state <= S_FETCH;	// o_fifo_rd asserted this cycle
                end

                S_FETCH: begin
                    state <= S_LOAD;
                end

                S_LOAD: begin
                    if (f_count == '0) begin
                        // empty fill - nothing to send
                        state <= S_NEXT;
                    end
                    else begin
                        o_cs_n   <= 1'b0;
                        o_dc     <= (f_type != T_CMD);
                        o_sclk   <= 1'b0;
                        is_pixel <= (f_type != T_CMD) && (f_type != T_DATA8);
                        word     <= f_data;
                        rep_left <= f_count;
                        if ((f_type == T_CMD) || (f_type == T_DATA8)) begin
                            shreg   <= {f_data[7:0], 8'h00};
                            bit_cnt <= 4'd7;
                        end
                        else begin
                            shreg   <= f_data;
                            bit_cnt <= 4'd15;
                        end
                        state <= S_SHIFT;
                    end
                end

                S_SHIFT: begin
                    if (tick) begin
                        if (!o_sclk) begin
                            o_sclk <= 1'b1;		// rising edge - panel samples
                        end
                        else begin
                            o_sclk <= 1'b0;		// falling edge - advance data
                            if (bit_cnt != 4'd0) begin
                                shreg   <= {shreg[14:0], 1'b0};
                                bit_cnt <= bit_cnt - 4'd1;
                            end
                            else if (is_pixel && (rep_left > 18'd1)) begin
                                // repeat the same pixel (hardware fill)
                                rep_left <= rep_left - 18'd1;
                                shreg    <= word;
                                bit_cnt  <= 4'd15;
                            end
                            else begin
                                state <= S_NEXT;
                            end
                        end
                    end
                end

                S_NEXT: begin
                    if (!i_fifo_empty)
                        state <= S_LOAD;		// popped this cycle, keep CS# low
                    else if (o_cs_n)
                        state <= S_IDLE;		// skipped a zero-count entry, CS# never asserted
                    else
                        state <= S_CSHOLD;
                end

                S_CSHOLD: begin
                    if (tick) begin
                        o_cs_n <= 1'b1;
                        state  <= S_CSGAP;
                    end
                end

                S_CSGAP: begin
                    if (tick)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule: lcd_spi_engine
