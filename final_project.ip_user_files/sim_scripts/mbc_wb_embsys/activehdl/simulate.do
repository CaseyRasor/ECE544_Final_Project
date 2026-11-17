transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+mbc_wb_embsys  -L xil_defaultlib -L xilinx_vip -L xpm -L microblaze_v11_0_17 -L lmb_v10_v3_0_16 -L lmb_bram_if_cntlr_v4_0_28 -L blk_mem_gen_v8_4_13 -L smartconnect_v1_0 -L proc_sys_reset_v5_0_17 -L axi_infrastructure_v1_1_0 -L axi_register_slice_v2_1_37 -L axi_vip_v1_1_23 -L axi_lite_ipif_v3_1_0 -L axi_intc_v4_1_23 -L mdm_v3_2_30 -L axi_uartlite_v2_0_40 -L axi_timer_v2_0_38 -L interrupt_control_v3_2_0 -L axi_gpio_v2_0_38 -L xilinx_vip -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.mbc_wb_embsys xil_defaultlib.glbl

do {mbc_wb_embsys.udo}

run 1000ns

endsim

quit -force
