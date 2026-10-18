# Pin assignments for top_uart_probe on the EDGE Spartan-7 (XC7S15-FTGB196-1).
# Every port of the top entity needs one line. LVCMOS33 = 3.3 V logic.
# PULLUP true on F2/G1: while the FPGA doesn't drive a pin, a weak pull-up holds
# it at '1' (the serial idle level), so a pin nobody drives can't fake a byte.

set_property -dict { PACKAGE_PIN H11  IOSTANDARD LVCMOS33 } [get_ports {clk}]   ;# 50 MHz oscillator
set_property -dict { PACKAGE_PIN F2   IOSTANDARD LVCMOS33 PULLUP true } [get_ports {pin_f2}]   ;# USB serial (manual: data FROM the PC)
set_property -dict { PACKAGE_PIN G1   IOSTANDARD LVCMOS33 PULLUP true } [get_ports {pin_g1}]   ;# USB serial (manual: data TO the PC)
set_property -dict { PACKAGE_PIN J12  IOSTANDARD LVCMOS33 } [get_ports {btn_send}]   ;# push button SW18 (PB3)
set_property -dict { PACKAGE_PIN L3   IOSTANDARD LVCMOS33 } [get_ports {seg_n[0]}]   ;# segment a
set_property -dict { PACKAGE_PIN P4   IOSTANDARD LVCMOS33 } [get_ports {seg_n[1]}]   ;# segment b
set_property -dict { PACKAGE_PIN P2   IOSTANDARD LVCMOS33 } [get_ports {seg_n[2]}]   ;# segment c
set_property -dict { PACKAGE_PIN M3   IOSTANDARD LVCMOS33 } [get_ports {seg_n[3]}]   ;# segment d
set_property -dict { PACKAGE_PIN M1   IOSTANDARD LVCMOS33 } [get_ports {seg_n[4]}]   ;# segment e
set_property -dict { PACKAGE_PIN J4   IOSTANDARD LVCMOS33 } [get_ports {seg_n[5]}]   ;# segment f
set_property -dict { PACKAGE_PIN K4   IOSTANDARD LVCMOS33 } [get_ports {seg_n[6]}]   ;# segment g
set_property -dict { PACKAGE_PIN J2   IOSTANDARD LVCMOS33 } [get_ports {seg_n[7]}]   ;# decimal point
set_property -dict { PACKAGE_PIN H1   IOSTANDARD LVCMOS33 } [get_ports {dig[0]}]   ;# DIGIT4 (rightmost)
set_property -dict { PACKAGE_PIN H2   IOSTANDARD LVCMOS33 } [get_ports {dig[1]}]   ;# DIGIT3
set_property -dict { PACKAGE_PIN H3   IOSTANDARD LVCMOS33 } [get_ports {dig[2]}]   ;# DIGIT2
set_property -dict { PACKAGE_PIN H4   IOSTANDARD LVCMOS33 } [get_ports {dig[3]}]   ;# DIGIT1 (leftmost)

# ---- clock and configuration settings (same in every design) ----
create_clock -name sys_clk -period 20.000 [get_ports {clk}]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
