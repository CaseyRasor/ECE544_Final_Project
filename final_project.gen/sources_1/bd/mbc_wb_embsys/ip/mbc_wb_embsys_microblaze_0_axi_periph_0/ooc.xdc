# aclk {FREQ_HZ 100000000 CLK_DOMAIN mbc_wb_embsys_Clk PHASE 0.0}
# Clock Domain: mbc_wb_embsys_Clk
create_clock -name aclk -period 10.000 [get_ports aclk]
# Generated clocks
