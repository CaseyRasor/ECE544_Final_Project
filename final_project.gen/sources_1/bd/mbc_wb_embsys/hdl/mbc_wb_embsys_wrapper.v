//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2026.1 (win64) Build 6511674 Tue Jun 16 11:02:23 MDT 2026
//Date        : Tue Nov 17 11:20:40 2026
//Host        : Casey_Desktop running 64-bit major release  (build 9200)
//Command     : generate_target mbc_wb_embsys_wrapper.bd
//Design      : mbc_wb_embsys_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module mbc_wb_embsys_wrapper
   (GPIO2_0_tri_o,
    GPIO_0_tri_o,
    m_wb_ack_0,
    m_wb_adr_0,
    m_wb_cyc_0,
    m_wb_dat_r_0,
    m_wb_dat_w_0,
    m_wb_err_0,
    m_wb_reset_0,
    m_wb_sel_0,
    m_wb_stall_0,
    m_wb_stb_0,
    m_wb_we_0,
    sysclk,
    sysreset_n,
    usb_uart_rxd,
    usb_uart_txd,
    wb_irq0,
    wb_irq1,
    wb_irq2);
  output [31:0]GPIO2_0_tri_o;
  output [31:0]GPIO_0_tri_o;
  input m_wb_ack_0;
  output [25:0]m_wb_adr_0;
  output m_wb_cyc_0;
  input [31:0]m_wb_dat_r_0;
  output [31:0]m_wb_dat_w_0;
  input m_wb_err_0;
  output m_wb_reset_0;
  output [3:0]m_wb_sel_0;
  input m_wb_stall_0;
  output m_wb_stb_0;
  output m_wb_we_0;
  input sysclk;
  input sysreset_n;
  input usb_uart_rxd;
  output usb_uart_txd;
  input [0:0]wb_irq0;
  input [0:0]wb_irq1;
  input [0:0]wb_irq2;

  wire [31:0]GPIO2_0_tri_o;
  wire [31:0]GPIO_0_tri_o;
  wire m_wb_ack_0;
  wire [25:0]m_wb_adr_0;
  wire m_wb_cyc_0;
  wire [31:0]m_wb_dat_r_0;
  wire [31:0]m_wb_dat_w_0;
  wire m_wb_err_0;
  wire m_wb_reset_0;
  wire [3:0]m_wb_sel_0;
  wire m_wb_stall_0;
  wire m_wb_stb_0;
  wire m_wb_we_0;
  wire sysclk;
  wire sysreset_n;
  wire usb_uart_rxd;
  wire usb_uart_txd;
  wire [0:0]wb_irq0;
  wire [0:0]wb_irq1;
  wire [0:0]wb_irq2;

  mbc_wb_embsys mbc_wb_embsys_i
       (.GPIO2_0_tri_o(GPIO2_0_tri_o),
        .GPIO_0_tri_o(GPIO_0_tri_o),
        .m_wb_ack_0(m_wb_ack_0),
        .m_wb_adr_0(m_wb_adr_0),
        .m_wb_cyc_0(m_wb_cyc_0),
        .m_wb_dat_r_0(m_wb_dat_r_0),
        .m_wb_dat_w_0(m_wb_dat_w_0),
        .m_wb_err_0(m_wb_err_0),
        .m_wb_reset_0(m_wb_reset_0),
        .m_wb_sel_0(m_wb_sel_0),
        .m_wb_stall_0(m_wb_stall_0),
        .m_wb_stb_0(m_wb_stb_0),
        .m_wb_we_0(m_wb_we_0),
        .sysclk(sysclk),
        .sysreset_n(sysreset_n),
        .usb_uart_rxd(usb_uart_rxd),
        .usb_uart_txd(usb_uart_txd),
        .wb_irq0(wb_irq0),
        .wb_irq1(wb_irq1),
        .wb_irq2(wb_irq2));
endmodule
