# Pin assignments for top_tetris on the EDGE Spartan-7 (XC7S15-FTGB196-1).
# Every port of the top entity needs one line. LVCMOS33 = 3.3 V logic.

set_property -dict { PACKAGE_PIN H11  IOSTANDARD LVCMOS33 } [get_ports {clk}]   ;# 50 MHz oscillator
set_property -dict { PACKAGE_PIN J14  IOSTANDARD LVCMOS33 } [get_ports {btn_left}]   ;# push button SW14 (left of the cross)
set_property -dict { PACKAGE_PIN J13  IOSTANDARD LVCMOS33 } [get_ports {btn_rot}]   ;# push button SW16 (top of the cross)
set_property -dict { PACKAGE_PIN J12  IOSTANDARD LVCMOS33 } [get_ports {btn_hard}]   ;# push button SW18 (centre of the cross)
set_property -dict { PACKAGE_PIN L13  IOSTANDARD LVCMOS33 } [get_ports {btn_soft}]   ;# push button SW23 (bottom of the cross)
set_property -dict { PACKAGE_PIN J11  IOSTANDARD LVCMOS33 } [get_ports {btn_right}]   ;# push button SW20 (right of the cross)
set_property -dict { PACKAGE_PIN K11  IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {sw_pause}]   ;# slide switch SW2
set_property -dict { PACKAGE_PIN M11  IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {sw_music}]   ;# slide switch SW4: music on
set_property -dict { PACKAGE_PIN N14  IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {sw_sfx}]   ;# slide switch SW5: sound effects on
set_property -dict { PACKAGE_PIN N10  IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {sw_usb}]   ;# slide switch SW7: link via USB (PC)
set_property -dict { PACKAGE_PIN L14  IOSTANDARD LVCMOS33 } [get_ports {link_tx}]   ;# J5 pin 5: to the other board
set_property -dict { PACKAGE_PIN M13  IOSTANDARD LVCMOS33 PULLUP true } [get_ports {link_rx}]   ;# J5 pin 6: from the other board (pull-up: unplugged = idle)
set_property -dict { PACKAGE_PIN F2   IOSTANDARD LVCMOS33 } [get_ports {usb_tx}]   ;# USB serial, to the PC
set_property -dict { PACKAGE_PIN G1   IOSTANDARD LVCMOS33 PULLUP true } [get_ports {usb_rx}]   ;# USB serial, from the PC
set_property -dict { PACKAGE_PIN A13  IOSTANDARD LVCMOS33 } [get_ports {audio_l}]   ;# audio jack left
set_property -dict { PACKAGE_PIN B13  IOSTANDARD LVCMOS33 } [get_ports {audio_r}]   ;# audio jack right
set_property -dict { PACKAGE_PIN B14  IOSTANDARD LVCMOS33 } [get_ports {buzzer}]   ;# buzzer (jumper J6 on Enable)
# Pin assignments for top_vga_bars on the EDGE Spartan-7 (XC7S15-FTGB196-1).
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
