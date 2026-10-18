@echo off
rem ===========================================================================
rem  sim.bat  -  run one testbench in Vivado's simulator (xsim), no board needed
rem
rem  Usage:   tools\sim.bat tb_uart_loop
rem           tools\sim.bat tb_vga_frame        (also writes sim\out\frame.png)
rem           tools\sim.bat tb_vga_frame 0      (picture: 0 bars, 1 ramps,
rem                                              2 grid, 3 square)
rem  The file list for each testbench is in sim\<name>.prj
rem  Look for "PASSED" / "FAILED" lines in the output.
rem ===========================================================================
setlocal
set "ROOT=%~dp0.."
pushd "%ROOT%"
set "ROOT=%CD%"
set "XBIN=D:\AMDDesignTools\2025.2\Vivado\bin"
if not exist "%XBIN%\xvhdl.bat" set "XBIN=D:\setup\FPGA_Builder_Package_V9\tools\vivado_min\2025.2\Vivado\bin"

set "TB=%~1"
if "%TB%"=="" (
  echo Usage: tools\sim.bat ^<testbench^>    e.g. tools\sim.bat tb_uart_loop
  popd & exit /b 1
)
set "GEN="
if not "%~2"=="" set GEN=-generic_top "PATTERN=%~2"

if not exist "%ROOT%\sim\out" mkdir "%ROOT%\sim\out"
pushd "%ROOT%\sim\out"
call "%XBIN%\xvhdl.bat" -prj "%ROOT%\sim\%TB%.prj" || goto :fail
call "%XBIN%\xelab.bat" %TB% %GEN% -s %TB%_snap -timescale 1ns/1ps || goto :fail
call "%XBIN%\xsim.bat" %TB%_snap -runall || goto :fail
if exist frame.ppm python "%ROOT%\tools\ppm2png.py" frame.ppm frame.png
popd & popd
exit /b 0

:fail
echo SIMULATION FAILED - see the messages above
popd & popd
exit /b 1
