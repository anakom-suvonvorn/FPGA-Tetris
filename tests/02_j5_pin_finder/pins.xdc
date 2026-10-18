# Pin assignments for top_j5_finder on the EDGE Spartan-7 (XC7S15-FTGB196-1).
# Every port of the top entity needs one line. LVCMOS33 = 3.3 V logic.

set_property -dict { PACKAGE_PIN H11  IOSTANDARD LVCMOS33 } [get_ports {clk}]   ;# 50 MHz oscillator
set_property -dict { PACKAGE_PIN J14  IOSTANDARD LVCMOS33 } [get_ports {btn_prev}]   ;# push button SW14 (PB1)
set_property -dict { PACKAGE_PIN J12  IOSTANDARD LVCMOS33 } [get_ports {btn_pause}]   ;# push button SW18 (PB3)
set_property -dict { PACKAGE_PIN L13  IOSTANDARD LVCMOS33 } [get_ports {btn_next}]   ;# push button SW23 (PB5)
set_property -dict { PACKAGE_PIN L14  IOSTANDARD LVCMOS33 } [get_ports {j5[0]}]   ;# J5 header pin 5
set_property -dict { PACKAGE_PIN M13  IOSTANDARD LVCMOS33 } [get_ports {j5[1]}]   ;# J5 header pin 6
set_property -dict { PACKAGE_PIN H14  IOSTANDARD LVCMOS33 } [get_ports {j5[2]}]   ;# J5 header pin 7
set_property -dict { PACKAGE_PIN H13  IOSTANDARD LVCMOS33 } [get_ports {j5[3]}]   ;# J5 header pin 8
set_property -dict { PACKAGE_PIN F11  IOSTANDARD LVCMOS33 } [get_ports {j5[4]}]   ;# J5 header pin 9
set_property -dict { PACKAGE_PIN G11  IOSTANDARD LVCMOS33 } [get_ports {j5[5]}]   ;# J5 header pin 10
set_property -dict { PACKAGE_PIN C14  IOSTANDARD LVCMOS33 } [get_ports {j5[6]}]   ;# J5 header pin 11
set_property -dict { PACKAGE_PIN D14  IOSTANDARD LVCMOS33 } [get_ports {j5[7]}]   ;# J5 header pin 12
set_property -dict { PACKAGE_PIN E13  IOSTANDARD LVCMOS33 } [get_ports {j5[8]}]   ;# J5 header pin 13
set_property -dict { PACKAGE_PIN F13  IOSTANDARD LVCMOS33 } [get_ports {j5[9]}]   ;# J5 header pin 14
set_property -dict { PACKAGE_PIN F14  IOSTANDARD LVCMOS33 } [get_ports {j5[10]}]   ;# J5 header pin 15
set_property -dict { PACKAGE_PIN G14  IOSTANDARD LVCMOS33 } [get_ports {j5[11]}]   ;# J5 header pin 16
set_property -dict { PACKAGE_PIN D13  IOSTANDARD LVCMOS33 } [get_ports {j5[12]}]   ;# J5 header pin 17
set_property -dict { PACKAGE_PIN D12  IOSTANDARD LVCMOS33 } [get_ports {j5[13]}]   ;# J5 header pin 18
set_property -dict { PACKAGE_PIN E12  IOSTANDARD LVCMOS33 } [get_ports {j5[14]}]   ;# J5 header pin 19
set_property -dict { PACKAGE_PIN F12  IOSTANDARD LVCMOS33 } [get_ports {j5[15]}]   ;# J5 header pin 20
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
