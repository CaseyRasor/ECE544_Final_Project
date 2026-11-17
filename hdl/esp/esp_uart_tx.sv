/**
 * @file	esp_uart_tx.sv
 * @brief	UART transmitter (8N1) for the ESP32 link
 *
 * @date	17-Nov-2026
 * @version	1.0
 *
 * @detail
 * Sends one start bit (0), eight data bits LSB first, and one stop bit (1),
 * each lasting i_div clock cycles.
 *
 *   - i_start is accepted only while o_busy is low; i_data is captured then.
 *   - o_busy stays high through the full stop bit, so starting the next
 *     character as soon as o_busy falls gives back-to-back characters.
 *   - o_tx idles high.
 */
 // SPDX-License-Identifier: MIT

`default_nettype wire

module esp_uart_tx (
    input  logic        i_clk,
    input  logic        i_rst,

    input  logic [15:0] i_div,		// clocks per bit (>= 8)
    input  logic        i_start,
    input  logic [7:0]  i_data,

    output logic        o_tx,
    output logic        o_busy
);

    logic [15:0] cnt;
    logic [3:0]  bits_left;	// bits still to send after the current one
    logic [8:0]  shreg;		// {stop, data[7:0]}

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            o_tx      <= 1'b1;
            o_busy    <= 1'b0;
            cnt       <= '0;
            bits_left <= '0;
            shreg     <= '1;
        end
        else if (!o_busy) begin
            o_tx <= 1'b1;
            if (i_start) begin
                o_tx      <= 1'b0;				// start bit
                shreg     <= {1'b1, i_data};
                bits_left <= 4'd9;
                cnt       <= i_div - 16'd1;
                o_busy    <= 1'b1;
            end
        end
        else if (cnt != 0) begin
            cnt <= cnt - 16'd1;
        end
        else if (bits_left != 0) begin
            o_tx      <= shreg[0];
            shreg     <= {1'b1, shreg[8:1]};
            bits_left <= bits_left - 4'd1;
            cnt       <= i_div - 16'd1;
        end
        else begin
            o_busy <= 1'b0;						// stop bit complete
        end
    end

endmodule: esp_uart_tx
