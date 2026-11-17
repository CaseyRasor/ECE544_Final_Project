@echo off
REM Run the wb_esp testbench with the Vivado simulator (xsim).
REM Usage: run from the sim\esp directory:  run_sim_esp.bat
set VIVADO_BIN=C:\AMDDesignTools\2026.1\Vivado\bin
set HDL=..\..\hdl

call %VIVADO_BIN%\xvlog.bat -sv ^
  %HDL%\lcd\lcd_fifo.sv ^
  %HDL%\esp\esp_uart_rx.sv ^
  %HDL%\esp\esp_uart_tx.sv ^
  %HDL%\esp\wb_esp.sv ^
  tb_wb_esp.sv || exit /b 1
call %VIVADO_BIN%\xelab.bat -debug typical tb_wb_esp -s tb_wb_esp_sim || exit /b 1
call %VIVADO_BIN%\xsim.bat tb_wb_esp_sim -runall
