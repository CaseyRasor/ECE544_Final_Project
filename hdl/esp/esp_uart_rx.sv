/**
 * @file	esp_uart_rx.sv
 * @brief	UART receiver (8N1) for the ESP32 link
 *
 * @date	17-Nov-2026
 * @version	1.0
 *
 * @detail
 * Classic mid-bit sampling receiver.  A falling edge on the (already
 * synchronized) input starts a character; the start bit is re-checked half a
 * bit later to reject glitches, then each data bit and the stop bit are
 * sampled one bit period apart, near the middle of the bit.
 *
 *   - i_div is the number of i_clk cycles per bit (100 MHz / baud).  It must be
 *     >= 8; wb_esp clamps the register so this always holds.
 *   - o_valid pulses for one cycle with the received byte on o_data.
 *   - o_frame_err pulses for one cycle if the stop bit is 0 (the byte is
 *     discarded).  The receiver then waits for the line to return high so a
 *     break condition is not decoded as a stream of 0x00 characters.
 *   - o_busy is high while a character is being received.
 */
 // SPDX-License-Identifier: MIT

`default_nettype wire

module esp_uart_rx (
    input  logic        i_clk,
    input  logic        i_rst,

    input  logic [15:0] i_div,		// clocks per bit (>= 8)
    input  logic        i_rx,		// synchronized serial input, idle high

    output logic        o_valid,
    output logic [7:0]  o_data,
    output logic        o_frame_err,
    output logic        o_busy
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_START,
        S_DATA,
        S_STOP,
        S_BREAK
    } state_t;

    state_t      state;
    logic [15:0] cnt;		// counts down to the next sample point
    logic [2:0]  bitn;
    logic [7:0]  shreg;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            state       <= S_IDLE;
            cnt         <= '0;
            bitn        <= '0;
            shreg       <= '0;
            o_data      <= '0;
            o_valid     <= 1'b0;
            o_frame_err <= 1'b0;
        end
        else begin
            o_valid     <= 1'b0;
            o_frame_err <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (!i_rx) begin
                        // first low sample of the start bit: wait half a bit
                        state <= S_START;
                        cnt   <= (i_div >> 1) - 16'd1;
                    end
                end

                S_START: begin
                    if (cnt != 0) begin
                        cnt <= cnt - 16'd1;
                    end
                    else if (i_rx) begin
                        state <= S_IDLE;			// glitch, not a start bit
                    end
                    else begin
                        state <= S_DATA;
                        cnt   <= i_div - 16'd1;
                        bitn  <= '0;
                    end
                end

                S_DATA: begin
                    if (cnt != 0) begin
                        cnt <= cnt - 16'd1;
                    end
                    else begin
                        shreg <= {i_rx, shreg[7:1]};	// LSB first
                        cnt   <= i_div - 16'd1;
                        bitn  <= bitn + 3'd1;
                        if (bitn == 3'd7)
                            state <= S_STOP;
                    end
                end

                S_STOP: begin
                    if (cnt != 0) begin
                        cnt <= cnt - 16'd1;
                    end
                    else if (i_rx) begin
                        o_valid <= 1'b1;
                        o_data  <= shreg;
                        state   <= S_IDLE;
                    end
                    else begin
                        o_frame_err <= 1'b1;
                        state       <= S_BREAK;
                    end
                end

                S_BREAK: begin
                    if (i_rx)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign o_busy = (state != S_IDLE);

endmodule: esp_uart_rx
