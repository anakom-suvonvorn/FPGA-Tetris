# Pin assignments for top_flash_read on the EDGE Spartan-7 (XC7S15-FTGB196-1).
# Every port of the top entity needs one line. LVCMOS33 = 3.3 V logic.
# The flash pins are the FPGA's configuration pins (bank 14). After the FPGA
# has loaded its bitstream they are ordinary pins we can use - except the
# clock pin CCLK (A8), which has no port here: it is driven through the
# STARTUPE2 primitive inside top_flash_read.vhd.

set_property -dict { PACKAGE_PIN H11  IOSTANDARD LVCMOS33 } [get_ports {clk}]   ;# 50 MHz oscillator
set_property -dict { PACKAGE_PIN J14  IOSTANDARD LVCMOS33 } [get_ports {btn_left}]   ;# SW14 cross left
set_property -dict { PACKAGE_PIN J13  IOSTANDARD LVCMOS33 } [get_ports {btn_up}]   ;# SW16 cross top
set_property -dict { PACKAGE_PIN J12  IOSTANDARD LVCMOS33 } [get_ports {btn_mid}]   ;# SW18 cross centre
set_property -dict { PACKAGE_PIN J11  IOSTANDARD LVCMOS33 } [get_ports {btn_right}]   ;# SW20 cross right
set_property -dict { PACKAGE_PIN L13  IOSTANDARD LVCMOS33 } [get_ports {btn_down}]   ;# SW23 cross bottom
set_property -dict { PACKAGE_PIN K11  IOSTANDARD LVCMOS33 } [get_ports {sw_spd0}]   ;# SW2 slide switch
set_property -dict { PACKAGE_PIN M11  IOSTANDARD LVCMOS33 } [get_ports {sw_spd1}]   ;# SW4 slide switch
set_property -dict { PACKAGE_PIN N14  IOSTANDARD LVCMOS33 } [get_ports {sw_sound}]   ;# SW5 slide switch
set_property -dict { PACKAGE_PIN C11  IOSTANDARD LVCMOS33 } [get_ports {flash_cs_n}]   ;# FCS_B  flash chip select
set_property -dict { PACKAGE_PIN B11  IOSTANDARD LVCMOS33 } [get_ports {flash_mosi}]   ;# D00_MOSI  data to the flash
set_property -dict { PACKAGE_PIN B12  IOSTANDARD LVCMOS33 PULLUP true } [get_ports {flash_miso}]   ;# D01_DIN  data from the flash
set_property -dict { PACKAGE_PIN D10  IOSTANDARD LVCMOS33 } [get_ports {flash_wp_n}]   ;# D02  flash WP#, held high
set_property -dict { PACKAGE_PIN C10  IOSTANDARD LVCMOS33 } [get_ports {flash_hold_n}]   ;# D03  flash HOLD#/RESET#, held high
set_property -dict { PACKAGE_PIN A13  IOSTANDARD LVCMOS33 } [get_ports {audio_l}]   ;# audio jack left
set_property -dict { PACKAGE_PIN B13  IOSTANDARD LVCMOS33 } [get_ports {audio_r}]   ;# audio jack right
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
