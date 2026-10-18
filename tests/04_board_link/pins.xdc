# Pin assignments for top_board_link on the EDGE Spartan-7 (XC7S15-FTGB196-1).
# Every port of the top entity needs one line. LVCMOS33 = 3.3 V logic.

set_property -dict { PACKAGE_PIN H11  IOSTANDARD LVCMOS33 } [get_ports {clk}]   ;# 50 MHz oscillator
set_property -dict { PACKAGE_PIN K11  IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]   ;# slide switch SW2
set_property -dict { PACKAGE_PIN M11  IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]   ;# slide switch SW4
set_property -dict { PACKAGE_PIN N14  IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]   ;# slide switch SW5
set_property -dict { PACKAGE_PIN P12  IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]   ;# slide switch SW6
set_property -dict { PACKAGE_PIN N10  IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]   ;# slide switch SW7
set_property -dict { PACKAGE_PIN P10  IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]   ;# slide switch SW8
set_property -dict { PACKAGE_PIN M10  IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]   ;# slide switch SW9
set_property -dict { PACKAGE_PIN N4   IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]   ;# slide switch SW10
set_property -dict { PACKAGE_PIN L14  IOSTANDARD LVCMOS33 } [get_ports {link_tx}]   ;# J5 header pin 5, to the OTHER board's pin 6
set_property -dict { PACKAGE_PIN M13  IOSTANDARD LVCMOS33 } [get_ports {link_rx}]   ;# J5 header pin 6, from the OTHER board's pin 5
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
