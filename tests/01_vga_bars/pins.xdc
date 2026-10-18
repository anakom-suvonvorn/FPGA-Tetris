# Pin assignments for top_vga_bars on the EDGE Spartan-7 (XC7S15-FTGB196-1).
# Every port of the top entity needs one line. LVCMOS33 = 3.3 V logic.

set_property -dict { PACKAGE_PIN H11  IOSTANDARD LVCMOS33 } [get_ports {clk}]   ;# 50 MHz oscillator
set_property -dict { PACKAGE_PIN K11  IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]   ;# slide switch SW2
set_property -dict { PACKAGE_PIN M11  IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]   ;# slide switch SW4
set_property -dict { PACKAGE_PIN B6   IOSTANDARD LVCMOS33 } [get_ports {vga_r[0]}]   ;# VGA RED0
set_property -dict { PACKAGE_PIN D3   IOSTANDARD LVCMOS33 } [get_ports {vga_r[1]}]   ;# VGA RED1
set_property -dict { PACKAGE_PIN C3   IOSTANDARD LVCMOS33 } [get_ports {vga_r[2]}]   ;# VGA RED2
set_property -dict { PACKAGE_PIN A4   IOSTANDARD LVCMOS33 } [get_ports {vga_r[3]}]   ;# VGA RED3
set_property -dict { PACKAGE_PIN A3   IOSTANDARD LVCMOS33 } [get_ports {vga_g[0]}]   ;# VGA GRN0
set_property -dict { PACKAGE_PIN B3   IOSTANDARD LVCMOS33 } [get_ports {vga_g[1]}]   ;# VGA GRN1
set_property -dict { PACKAGE_PIN A2   IOSTANDARD LVCMOS33 } [get_ports {vga_g[2]}]   ;# VGA GRN2
set_property -dict { PACKAGE_PIN B5   IOSTANDARD LVCMOS33 } [get_ports {vga_g[3]}]   ;# VGA GRN3
set_property -dict { PACKAGE_PIN A5   IOSTANDARD LVCMOS33 } [get_ports {vga_b[0]}]   ;# VGA BLU0
set_property -dict { PACKAGE_PIN B2   IOSTANDARD LVCMOS33 } [get_ports {vga_b[1]}]   ;# VGA BLU1
set_property -dict { PACKAGE_PIN B1   IOSTANDARD LVCMOS33 } [get_ports {vga_b[2]}]   ;# VGA BLU2
set_property -dict { PACKAGE_PIN C5   IOSTANDARD LVCMOS33 } [get_ports {vga_b[3]}]   ;# VGA BLU3
set_property -dict { PACKAGE_PIN C4   IOSTANDARD LVCMOS33 } [get_ports {vga_hs}]   ;# VGA HSYNC
set_property -dict { PACKAGE_PIN E4   IOSTANDARD LVCMOS33 } [get_ports {vga_vs}]   ;# VGA VSYNC

# ---- clock and configuration settings (same in every design) ----
create_clock -name sys_clk -period 20.000 [get_ports {clk}]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
