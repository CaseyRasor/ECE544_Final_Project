transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib activehdl/xilinx_vip
vlib activehdl/xpm
vlib activehdl/microblaze_v11_0_17
vlib activehdl/xil_defaultlib
vlib activehdl/lmb_v10_v3_0_16
vlib activehdl/lmb_bram_if_cntlr_v4_0_28
vlib activehdl/blk_mem_gen_v8_4_13
vlib activehdl/smartconnect_v1_0
vlib activehdl/proc_sys_reset_v5_0_17
vlib activehdl/axi_infrastructure_v1_1_0
vlib activehdl/axi_register_slice_v2_1_37
vlib activehdl/axi_vip_v1_1_23
vlib activehdl/axi_lite_ipif_v3_1_0
vlib activehdl/axi_intc_v4_1_23
vlib activehdl/mdm_v3_2_30
vlib activehdl/axi_uartlite_v2_0_40
vlib activehdl/axi_timer_v2_0_38
vlib activehdl/interrupt_control_v3_2_0
vlib activehdl/axi_gpio_v2_0_38

vmap xilinx_vip activehdl/xilinx_vip
vmap xpm activehdl/xpm
vmap microblaze_v11_0_17 activehdl/microblaze_v11_0_17
vmap xil_defaultlib activehdl/xil_defaultlib
vmap lmb_v10_v3_0_16 activehdl/lmb_v10_v3_0_16
vmap lmb_bram_if_cntlr_v4_0_28 activehdl/lmb_bram_if_cntlr_v4_0_28
vmap blk_mem_gen_v8_4_13 activehdl/blk_mem_gen_v8_4_13
vmap smartconnect_v1_0 activehdl/smartconnect_v1_0
vmap proc_sys_reset_v5_0_17 activehdl/proc_sys_reset_v5_0_17
vmap axi_infrastructure_v1_1_0 activehdl/axi_infrastructure_v1_1_0
vmap axi_register_slice_v2_1_37 activehdl/axi_register_slice_v2_1_37
vmap axi_vip_v1_1_23 activehdl/axi_vip_v1_1_23
vmap axi_lite_ipif_v3_1_0 activehdl/axi_lite_ipif_v3_1_0
vmap axi_intc_v4_1_23 activehdl/axi_intc_v4_1_23
vmap mdm_v3_2_30 activehdl/mdm_v3_2_30
vmap axi_uartlite_v2_0_40 activehdl/axi_uartlite_v2_0_40
vmap axi_timer_v2_0_38 activehdl/axi_timer_v2_0_38
vmap interrupt_control_v3_2_0 activehdl/interrupt_control_v3_2_0
vmap axi_gpio_v2_0_38 activehdl/axi_gpio_v2_0_38

vlog -work xilinx_vip  -sv2k12 "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_axi4streampc.sv" \
"C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/hdl/axi_vip_axi4pc.sv" \
"C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/hdl/xil_common_vip_pkg.sv" \
"C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_pkg.sv" \
"C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/hdl/axi_vip_pkg.sv" \
"C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_if.sv" \
"C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/hdl/axi_vip_if.sv" \
"C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/hdl/clk_vip_if.sv" \
"C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/hdl/rst_vip_if.sv" \

vlog -work xpm  -sv2k12 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"C:/AMDDesignTools/2026.1/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"C:/AMDDesignTools/2026.1/Vivado/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"C:/AMDDesignTools/2026.1/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93  \
"C:/AMDDesignTools/2026.1/Vivado/data/ip/xpm/xpm_VCOMP.vhd" \

vcom -work microblaze_v11_0_17 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/959b/hdl/microblaze_v11_0_rfs.vhd" \

vcom -work xil_defaultlib -93  \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_microblaze_0_0/sim/mbc_wb_embsys_microblaze_0_0.vhd" \

vcom -work lmb_v10_v3_0_16 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/dac4/hdl/lmb_v10_v3_0_vh_rfs.vhd" \

vcom -work xil_defaultlib -93  \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_dlmb_v10_0/sim/mbc_wb_embsys_dlmb_v10_0.vhd" \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_ilmb_v10_0/sim/mbc_wb_embsys_ilmb_v10_0.vhd" \

vcom -work lmb_bram_if_cntlr_v4_0_28 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/a190/hdl/lmb_bram_if_cntlr_v4_0_rfs.vhd" \

vcom -work xil_defaultlib -93  \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_dlmb_bram_if_cntlr_0/sim/mbc_wb_embsys_dlmb_bram_if_cntlr_0.vhd" \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_ilmb_bram_if_cntlr_0/sim/mbc_wb_embsys_ilmb_bram_if_cntlr_0.vhd" \

vlog -work blk_mem_gen_v8_4_13  -v2k5 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/59f9/simulation/blk_mem_gen_v8_4.v" \

vlog -work xil_defaultlib  -v2k5 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_lmb_bram_0/sim/mbc_wb_embsys_lmb_bram_0.v" \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_microblaze_0_axi_periph_0/bd_0/sim/bd_84d2.v" \

vlog -work smartconnect_v1_0  -sv2k12 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/sc_util_v1_0_vl_rfs.sv" \

vcom -work proc_sys_reset_v5_0_17 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/9438/hdl/proc_sys_reset_v5_0_rfs.vhd" \

vcom -work smartconnect_v1_0 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/21d5/hdl/sc_ultralite_v1_0_rfs.vhd" \

vlog -work smartconnect_v1_0  -sv2k12 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/21d5/hdl/sc_ultralite_v1_0_rfs.sv" \

vlog -work xil_defaultlib  -sv2k12 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_microblaze_0_axi_periph_0/bd_0/ip/ip_0/sim/bd_84d2_sc_ul_0.sv" \

vlog -work smartconnect_v1_0  -sv2k12 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/3d9a/hdl/sc_mmu_v1_0_vl_rfs.sv" \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/7785/hdl/sc_transaction_regulator_v1_0_vl_rfs.sv" \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/3051/hdl/sc_si_converter_v1_0_vl_rfs.sv" \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/sc_node_v1_0_vl_rfs.sv" \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/0848/hdl/sc_switchboard_v1_0_vl_rfs.sv" \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/852f/hdl/sc_axi2sc_v1_0_vl_rfs.sv" \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/fca9/hdl/sc_sc2axi_v1_0_vl_rfs.sv" \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/c7d2/hdl/sc_exit_v1_0_vl_rfs.sv" \

vlog -work axi_infrastructure_v1_1_0  -v2k5 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl/axi_infrastructure_v1_1_vl_rfs.v" \

vlog -work axi_register_slice_v2_1_37  -v2k5 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/8c55/hdl/axi_register_slice_v2_1_rfs.v" \

vlog -work axi_vip_v1_1_23  -sv2k12 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/4d28/hdl/axi_vip_v1_1_vl_rfs.sv" \

vlog -work xil_defaultlib  -sv2k12 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_microblaze_0_axi_periph_0/sim/mbc_wb_embsys_microblaze_0_axi_periph_0.sv" \

vcom -work axi_lite_ipif_v3_1_0 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/de33/hdl/axi_lite_ipif_v3_1_rfs.vhd" \

vcom -work axi_intc_v4_1_23 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ca9d/hdl/axi_intc_v4_1_rfs.vhd" \

vcom -work xil_defaultlib -93  \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_microblaze_0_axi_intc_0/sim/mbc_wb_embsys_microblaze_0_axi_intc_0.vhd" \

vcom -work mdm_v3_2_30 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/23b0/hdl/mdm_v3_2_rfs.vhd" \

vcom -work xil_defaultlib -93  \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_mdm_1_0/sim/mbc_wb_embsys_mdm_1_0.vhd" \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_rst_Clk_100M_0/sim/mbc_wb_embsys_rst_Clk_100M_0.vhd" \

vcom -work axi_uartlite_v2_0_40 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/b7ff/hdl/axi_uartlite_v2_0_rfs.vhd" \

vcom -work xil_defaultlib -93  \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_axi_uartlite_0_0/sim/mbc_wb_embsys_axi_uartlite_0_0.vhd" \

vcom -work axi_timer_v2_0_38 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/c960/hdl/axi_timer_v2_0_rfs.vhd" \

vcom -work xil_defaultlib -93  \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_axi_timer_0_0/sim/mbc_wb_embsys_axi_timer_0_0.vhd" \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_axi_timer_1_0/sim/mbc_wb_embsys_axi_timer_1_0.vhd" \

vlog -work xil_defaultlib  -v2k5 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../bd/mbc_wb_embsys/ipshared/ce2b/src/axilrd2wbsp.v" \
"../../../bd/mbc_wb_embsys/ipshared/ce2b/src/axilwr2wbsp.v" \
"../../../bd/mbc_wb_embsys/ipshared/ce2b/src/axlite2wbsp.v" \
"../../../bd/mbc_wb_embsys/ipshared/ce2b/src/wbarbiter.v" \

vcom -work xil_defaultlib -93  \
"../../../bd/mbc_wb_embsys/ipshared/ce2b/src/axlite_wrapper.vhd" \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_axlite2wbsp_0_0/sim/mbc_wb_embsys_axlite2wbsp_0_0.vhd" \

vcom -work interrupt_control_v3_2_0 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/e2ca/hdl/interrupt_control_v3_2_rfs.vhd" \

vcom -work axi_gpio_v2_0_38 -93  \
"../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/6ccd/hdl/axi_gpio_v2_0_rfs.vhd" \

vcom -work xil_defaultlib -93  \
"../../../bd/mbc_wb_embsys/ip/mbc_wb_embsys_axi_gpio_0_1/sim/mbc_wb_embsys_axi_gpio_0_1.vhd" \

vlog -work xil_defaultlib  -v2k5 "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/f0b6/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/00fe/hdl/verilog" "+incdir+../../../../final_project.gen/sources_1/bd/mbc_wb_embsys/ipshared/ec67/hdl" "+incdir+../../../../../../../../AMDDesignTools/2026.1/Vivado/data/rsb/busdef" "+incdir+C:/AMDDesignTools/2026.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l microblaze_v11_0_17 -l xil_defaultlib -l lmb_v10_v3_0_16 -l lmb_bram_if_cntlr_v4_0_28 -l blk_mem_gen_v8_4_13 -l smartconnect_v1_0 -l proc_sys_reset_v5_0_17 -l axi_infrastructure_v1_1_0 -l axi_register_slice_v2_1_37 -l axi_vip_v1_1_23 -l axi_lite_ipif_v3_1_0 -l axi_intc_v4_1_23 -l mdm_v3_2_30 -l axi_uartlite_v2_0_40 -l axi_timer_v2_0_38 -l interrupt_control_v3_2_0 -l axi_gpio_v2_0_38 \
"../../../bd/mbc_wb_embsys/sim/mbc_wb_embsys.v" \

vlog -work xil_defaultlib \
"glbl.v"

