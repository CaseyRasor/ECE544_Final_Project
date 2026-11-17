-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
-- -------------------------------------------------------------------------------
-- This file contains confidential and proprietary information
-- of AMD and is protected under U.S. and international copyright
-- and other intellectual property laws.
--
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- AMD, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) AMD shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or AMD had been advised of the
-- possibility of the same.
--
-- CRITICAL APPLICATIONS
-- AMD products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of AMD products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
--
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
--
-- DO NOT MODIFY THIS FILE.

-- MODULE VLNV: amd.com:blockdesign:mbc_wb_embsys:1.0

-- The following code must appear in the VHDL architecture header.

-- COMP_TAG     ------ Begin cut for COMPONENT Declaration ------
COMPONENT mbc_wb_embsys
  PORT (
    usb_uart_rxd : IN STD_LOGIC;
    usb_uart_txd : OUT STD_LOGIC;
    GPIO_0_tri_o : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    GPIO2_0_tri_o : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    sysclk : IN STD_LOGIC;
    sysreset_n : IN STD_LOGIC;
    wb_irq0 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    wb_irq1 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    m_wb_ack_0 : IN STD_LOGIC;
    m_wb_adr_0 : OUT STD_LOGIC_VECTOR(25 DOWNTO 0);
    m_wb_cyc_0 : OUT STD_LOGIC;
    m_wb_dat_r_0 : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_wb_dat_w_0 : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_wb_err_0 : IN STD_LOGIC;
    m_wb_reset_0 : OUT STD_LOGIC;
    m_wb_sel_0 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    m_wb_stall_0 : IN STD_LOGIC;
    m_wb_stb_0 : OUT STD_LOGIC;
    m_wb_we_0 : OUT STD_LOGIC;
    wb_irq2 : IN STD_LOGIC_VECTOR(0 DOWNTO 0)
  );
END COMPONENT;
-- COMP_TAG_END ------  End cut for COMPONENT Declaration  ------

-- The following code must appear in the VHDL architecture
-- body. Substitute your own instance name and net names.

-- INST_TAG     ------ Begin cut for INSTANTIATION Template ------
your_instance_name : mbc_wb_embsys
  PORT MAP (
    usb_uart_rxd => usb_uart_rxd,
    usb_uart_txd => usb_uart_txd,
    GPIO_0_tri_o => GPIO_0_tri_o,
    GPIO2_0_tri_o => GPIO2_0_tri_o,
    sysclk => sysclk,
    sysreset_n => sysreset_n,
    wb_irq0 => wb_irq0,
    wb_irq1 => wb_irq1,
    m_wb_ack_0 => m_wb_ack_0,
    m_wb_adr_0 => m_wb_adr_0,
    m_wb_cyc_0 => m_wb_cyc_0,
    m_wb_dat_r_0 => m_wb_dat_r_0,
    m_wb_dat_w_0 => m_wb_dat_w_0,
    m_wb_err_0 => m_wb_err_0,
    m_wb_reset_0 => m_wb_reset_0,
    m_wb_sel_0 => m_wb_sel_0,
    m_wb_stall_0 => m_wb_stall_0,
    m_wb_stb_0 => m_wb_stb_0,
    m_wb_we_0 => m_wb_we_0,
    wb_irq2 => wb_irq2
  );
-- INST_TAG_END ------  End cut for INSTANTIATION Template  ------

-- You must compile the wrapper file mbc_wb_embsys.vhd when simulating
-- the module, mbc_wb_embsys. When compiling the wrapper file, be sure to
-- reference the VHDL simulation library.
