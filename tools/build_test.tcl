# ============================================================================
# build_test.tcl  -  build one design to a .bit file with Vivado (batch mode)
#
# Normally run through tools\build.bat, e.g.:   tools\build.bat 01_vga_bars
#
# It does the same steps as the TA's FPGA Builder, plus two reports the
# Builder does not give you:
#   build\timing.txt       did the design meet the 50 MHz timing?  (WNS >= 0)
#   build\utilization.txt  how much of the FPGA is used (LUTs, flip-flops, BRAM)
# Both are useful for the design document.
#
# Arguments: <project root>  <design folder>
# The design folder must contain project.txt (top + file list) and pins.xdc.
# ============================================================================
set root [file normalize [lindex $argv 0]]
set tdir [file normalize [lindex $argv 1]]
set bdir "$tdir/build"
file mkdir $bdir

# ---- read project.txt ----
set fh [open "$tdir/project.txt" r]
set lines [split [read $fh] "\n"]
close $fh
set top ""
set files {}
foreach l $lines {
  set l [string trim $l]
  if {$l eq "" || [string index $l 0] eq "#"} { continue }
  if {[string match "top=*" $l]} {
    set top [string range $l 4 end]
  } else {
    lappend files "$root/$l"
  }
}
if {$top eq ""} { error "project.txt has no top= line" }

catch {config_webtalk -install off}

# ---- read sources and pins ----
foreach f $files { read_vhdl $f }
read_xdc "$tdir/pins.xdc"

# ---- synthesis, place, route ----
synth_design -top $top -part xc7s15ftgb196-1
opt_design
place_design
route_design

# ---- reports ----
report_utilization     -file "$bdir/utilization.txt"
report_utilization -hierarchical -file "$bdir/utilization_by_block.txt"
report_timing_summary  -file "$bdir/timing.txt"
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "=================================================="
puts " DESIGN : $top"
puts " WNS    : $wns ns   (must be >= 0, otherwise timing failed)"
puts "=================================================="

# ---- bitstream ----
write_bitstream -force "$bdir/$top.bit"
puts "Wrote $bdir/$top.bit"
