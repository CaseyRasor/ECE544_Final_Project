@echo off
REM Run the wb_lcd testbench with the Vivado simulator (xsim).
REM Usage: run from the sim directory:  run_sim.bat
set VIVADO_BIN=C:\AMDDesignTools\2026.1\Vivado\bin
set HDL=..\hdl

call %VIVADO_BIN%\xvlog.bat -sv ^
  %HDL%\cdc\sync_reset.sv ^
  %HDL%\boardio\rgbPWM.v ^
  %HDL%\boardio\wb_boardio.sv ^
  %HDL%\sevenseg\sevensegment.sv ^
  %HDL%\sevenseg\wb_sevenseg.sv ^
  %HDL%\wishbone\wb_err.sv ^
  %HDL%\wishbone\wb_mux.sv ^
  %HDL%\lcd\lcd_fifo.sv ^
  %HDL%\lcd\lcd_spi_engine.sv ^
  %HDL%\lcd\wb_lcd.sv ^
  %HDL%\esp\esp_uart_rx.sv ^
  %HDL%\esp\esp_uart_tx.sv ^
  %HDL%\esp\wb_esp.sv ^
  %HDL%\wishbone\wb_subsystem.sv ^
  tb_wb_lcd.sv || exit /b 1
call %VIVADO_BIN%\xelab.bat -debug typical tb_wb_lcd -s tb_wb_lcd_sim || exit /b 1
call %VIVADO_BIN%\xsim.bat tb_wb_lcd_sim -runall
