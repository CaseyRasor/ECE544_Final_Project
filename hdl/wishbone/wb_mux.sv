/**
 * @file	wb_mux.sv
 * @brief	Wishbone bus mux: up to 8 x 64 KB regions, with an error device
 *
 * @author	Roy Kravitz (roy.kravitz@pdx.edu) and CoPilot
 * @date	28-Apr-2026
 * @version	3.0
 *
 * @detail
 * Creates/multiplexes signals for the custom Wishbone peripherals and a wb_err
 * peripheral, which generates an ACK for any region that has no device.  The
 * wb_err peripheral is needed because the WB bus will hang on an access that
 * isn't ACK/NAK'd.
 *
 * i_wb_addr[18:16] select one of 8 regions.  Each peripheral has a 64 KB MMIO
 * register/data space, although a typical peripheral uses only a few
 * registers.  Region map (offsets from the axlite2wbsp base address):
 *
 *   region  offset    device
 *     0     0x00000   slave 0  - board I/O (LEDs, switches, buttons, RGB LEDs)
 *     1     0x10000   slave 1  - seven-segment display
 *     2     0x20000   wb_err   - no device (kept for address compatibility)
 *     3     0x30000   slave 3  - ST7796S SPI LCD
 *     4     0x40000   slave 4  - ESP32 UART link
 *     5-7   0x50000+  wb_err   - free
 *
 * The axlite2wbsp address segment in the block design must cover all regions
 * that are used: 256K reaches regions 0-3, 512K reaches regions 0-7.
 *
 * To add a device in a free region: add an o_sN_* / i_sN_* port group, drive
 * its cyc/stb from (region == N), and add region N to the ACK and data muxes.
 *
 * This module is intended to work w/ axi2wbsp
 * (https://github.com/ZipCPU/wb2axip/blob/master/rtl/axim2wbsp.v)
 */

`default_nettype wire

module wb_mux #(
    parameter int DW = 32,
    parameter int AW = 32
)(
    input  logic            i_clk,
    input  logic            i_reset,

    // Wishbone master input from axilite2wbsp AXI to Wishbone Bus bridge
    input  logic            i_wb_cyc,
    input  logic            i_wb_stb,
    input  logic            i_wb_we,
    input  logic [AW-1:0]   i_wb_addr,
    input  logic [DW-1:0]   i_wb_data,
    input  logic [DW/8-1:0] i_wb_sel,

    // Slave 0 (board I/O)
    output logic            o_s0_cyc,
    output logic            o_s0_stb,
    output logic            o_s0_we,
    output logic [AW-1:0]   o_s0_addr,
    output logic [DW-1:0]   o_s0_data,
    output logic [DW/8-1:0] o_s0_sel,
    input  logic            i_s0_ack,
    input  logic [DW-1:0]   i_s0_data,

    // Slave 1 (Seven-seg)
    output logic            o_s1_cyc,
    output logic            o_s1_stb,
    output logic            o_s1_we,
    output logic [AW-1:0]   o_s1_addr,
    output logic [DW-1:0]   o_s1_data,
    output logic [DW/8-1:0] o_s1_sel,
    input  logic            i_s1_ack,
    input  logic [DW-1:0]   i_s1_data,

    // Error slave (region 2 and every unused region)
    output logic            o_err_cyc,
    output logic            o_err_stb,
    output logic            o_err_we,
    output logic [AW-1:0]   o_err_addr,
    output logic [DW-1:0]   o_err_data,
    output logic [DW/8-1:0] o_err_sel,
    input  logic            i_err_ack,
    input  logic [DW-1:0]   i_err_data,

    // Slave 3 (ST7796S LCD)
    output logic            o_s3_cyc,
    output logic            o_s3_stb,
    output logic            o_s3_we,
    output logic [AW-1:0]   o_s3_addr,
    output logic [DW-1:0]   o_s3_data,
    output logic [DW/8-1:0] o_s3_sel,
    input  logic            i_s3_ack,
    input  logic [DW-1:0]   i_s3_data,

    // Slave 4 (ESP32 UART link)
    output logic            o_s4_cyc,
    output logic            o_s4_stb,
    output logic            o_s4_we,
    output logic [AW-1:0]   o_s4_addr,
    output logic [DW-1:0]   o_s4_data,
    output logic [DW/8-1:0] o_s4_sel,
    input  logic            i_s4_ack,
    input  logic [DW-1:0]   i_s4_data,

    // Muxed output to master
    output logic            o_wb_ack,
    output logic [DW-1:0]   o_wb_data
);

    localparam logic [2:0] R_S0 = 3'd0;
    localparam logic [2:0] R_S1 = 3'd1;
    localparam logic [2:0] R_S3 = 3'd3;
    localparam logic [2:0] R_S4 = 3'd4;

    // Decode 64 KB regions using address bits [18:16]
    logic [2:0] region;
    logic       sel_s0, sel_s1, sel_s3, sel_s4, sel_err;

    assign region  = i_wb_addr[18:16];
    assign sel_s0  = (region == R_S0);
    assign sel_s1  = (region == R_S1);
    assign sel_s3  = (region == R_S3);
    assign sel_s4  = (region == R_S4);
    assign sel_err = !(sel_s0 || sel_s1 || sel_s3 || sel_s4);

    // Drive all slave address/data lines
    assign o_s0_addr  = i_wb_addr;
    assign o_s1_addr  = i_wb_addr;
    assign o_err_addr = i_wb_addr;
    assign o_s3_addr  = i_wb_addr;
    assign o_s4_addr  = i_wb_addr;

    assign o_s0_data  = i_wb_data;
    assign o_s1_data  = i_wb_data;
    assign o_err_data = i_wb_data;
    assign o_s3_data  = i_wb_data;
    assign o_s4_data  = i_wb_data;

    assign o_s0_sel   = i_wb_sel;
    assign o_s1_sel   = i_wb_sel;
    assign o_err_sel  = i_wb_sel;
    assign o_s3_sel   = i_wb_sel;
    assign o_s4_sel   = i_wb_sel;

    // Generate cyc/stb/we per slave
    assign o_s0_cyc  = i_wb_cyc && sel_s0;
    assign o_s0_stb  = i_wb_stb && sel_s0;
    assign o_s0_we   = i_wb_we;

    assign o_s1_cyc  = i_wb_cyc && sel_s1;
    assign o_s1_stb  = i_wb_stb && sel_s1;
    assign o_s1_we   = i_wb_we;

    assign o_err_cyc = i_wb_cyc && sel_err;
    assign o_err_stb = i_wb_stb && sel_err;
    assign o_err_we  = i_wb_we;

    assign o_s3_cyc  = i_wb_cyc && sel_s3;
    assign o_s3_stb  = i_wb_stb && sel_s3;
    assign o_s3_we   = i_wb_we;

    assign o_s4_cyc  = i_wb_cyc && sel_s4;
    assign o_s4_stb  = i_wb_stb && sel_s4;
    assign o_s4_we   = i_wb_we;

    // ACK mux
    always_comb begin
        case (region)
            R_S0:    o_wb_ack = i_s0_ack;
            R_S1:    o_wb_ack = i_s1_ack;
            R_S3:    o_wb_ack = i_s3_ack;
            R_S4:    o_wb_ack = i_s4_ack;
            default: o_wb_ack = i_err_ack;
        endcase
    end

    // Data mux
    always_comb begin
        case (region)
            R_S0:    o_wb_data = i_s0_data;
            R_S1:    o_wb_data = i_s1_data;
            R_S3:    o_wb_data = i_s3_data;
            R_S4:    o_wb_data = i_s4_data;
            default: o_wb_data = i_err_data;
        endcase
    end

endmodule : wb_mux
