# ============================================================================
# make_vivado_project.tcl  -  turn one of our designs into a Vivado GUI project
#
# Normally run through tools\vivado_gui.bat, e.g.:
#     tools\vivado_gui.bat 05_uart_probe tb_uart_probe
#
# Creates  vivado\<design>\<design>.xpr  with:
#   * the VHDL files from project.txt (LINKED, not copied: when you edit a
#     file in VS Code, Vivado sees the change)
#   * pins.xdc as the constraints file
#   * optionally a testbench from sim\ as the simulation top
# The project folder is throw-away: delete it any time and make it again.
#
# Arguments: <project root> <design folder> [testbench name]
# ============================================================================
set root [file normalize [lindex $argv 0]]
set tdir [file normalize [lindex $argv 1]]
set tb   ""
if {[llength $argv] > 2} { set tb [lindex $argv 2] }
set name [file tail $tdir]
set pdir "$root/vivado/$name"

# ---- read project.txt (same format as build_test.tcl) ----
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

# ---- new project (overwrite an old one of the same name) ----
create_project $name $pdir -part xc7s15ftgb196-1 -force
set_property target_language VHDL [current_project]
set_property simulator_language VHDL [current_project]

# design sources: linked, plain VHDL (-93), same as the TA Builder reads them
add_files -norecurse -fileset sources_1 $files
set_property file_type VHDL [get_files -of_objects [get_filesets sources_1]]
set_property top $top [get_filesets sources_1]

# constraints
add_files -norecurse -fileset constrs_1 "$tdir/pins.xdc"

# simulation: our testbench, run until it finishes by itself
if {$tb ne ""} {
  add_files -norecurse -fileset sim_1 "$root/sim/$tb.vhd"
  set_property file_type VHDL [get_files "$root/sim/$tb.vhd"]
  set_property top $tb [get_filesets sim_1]
  set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]
}

update_compile_order -fileset sources_1
if {$tb ne ""} { update_compile_order -fileset sim_1 }
close_project
puts "Created $pdir/$name.xpr"
