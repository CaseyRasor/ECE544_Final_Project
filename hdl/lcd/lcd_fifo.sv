/**
 * @file	lcd_fifo.sv
 * @brief	Single-clock FIFO for the LCD (ST7796S) transmit queue
 *
 * @date	16-Nov-2026
 * @version	1.0
 *
 * @detail
 * Simple synchronous FIFO intended to infer a single block RAM
 * (512 x 36 = one RAMB18 in 512x36 mode with the default parameters).
 *
 *   - i_wr pushes i_din when not full (writes while full are ignored)
 *   - i_rd pops one entry when not empty; o_dout is valid the cycle AFTER i_rd
 *     (registered read, standard BRAM behaviour - NOT first-word-fall-through)
 *   - i_clr synchronously empties the FIFO
 *   - o_level is the number of entries currently stored (0..DEPTH)
 */
 // SPDX-License-Identifier: MIT

`default_nettype wire

module lcd_fifo #(
    parameter int W  = 36,		// entry width
    parameter int LG = 9		// log2(depth)
) (
    input  logic          i_clk,
    input  logic          i_rst,
    input  logic          i_clr,

    input  logic          i_wr,
    input  logic [W-1:0]  i_din,

    input  logic          i_rd,
    output logic [W-1:0]  o_dout,

    output logic          o_full,
    output logic          o_empty,
    output logic [LG:0]   o_level
);

    (* ram_style = "block" *) logic [W-1:0] mem [0:(1<<LG)-1];

    logic [LG-1:0] wr_ptr, rd_ptr;
    logic [LG:0]   count;

    logic do_wr, do_rd;

    assign o_full  = (count == (LG+1)'(1 << LG));
    assign o_empty = (count == '0);
    assign o_level = count;

    assign do_wr = i_wr && !o_full;
    assign do_rd = i_rd && !o_empty;

    // memory (no reset so it maps to BRAM)
    always_ff @(posedge i_clk) begin
        if (do_wr)
            mem[wr_ptr] <= i_din;
        if (do_rd)
            o_dout <= mem[rd_ptr];
    end

    // pointers and occupancy
    always_ff @(posedge i_clk) begin
        if (i_rst || i_clr) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end
        else begin
            if (do_wr) wr_ptr <= wr_ptr + 1'b1;
            if (do_rd) rd_ptr <= rd_ptr + 1'b1;

            case ({do_wr, do_rd})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule: lcd_fifo
