onbreak {quit -f}
onerror {quit -f}

vsim  -lib xil_defaultlib mbc_wb_embsys_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure
view signals

do {mbc_wb_embsys.udo}

run 1000ns

quit -force
