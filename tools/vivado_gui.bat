@echo off
rem ===========================================================================
rem  vivado_gui.bat  -  open one of our designs in the Vivado GUI
rem
rem  Usage:   tools\vivado_gui.bat 01_vga_bars tb_vga_frame
rem           tools\vivado_gui.bat 05_uart_probe tb_uart_probe
rem           tools\vivado_gui.bat 02_j5_pin_finder          (no testbench)
rem
rem  Makes a Vivado project in vivado\<design>\ (files are linked, not copied)
rem  and opens it. See docs\learn\04_vivado.md for what to click.
rem  Running it again rebuilds the project from scratch (your VHDL is safe,
rem  it lives in src\ and tests\, not in the project folder).
rem ===========================================================================
setlocal
set "ROOT=%~dp0.."
pushd "%ROOT%"
set "ROOT=%CD%"

if "%~1"=="" (
  echo Usage: tools\vivado_gui.bat ^<design folder name^> [testbench]
  popd & exit /b 1
)
set "TDIR=%ROOT%\tests\%~1"
if not exist "%TDIR%\project.txt" set "TDIR=%ROOT%\%~1"
if not exist "%TDIR%\project.txt" (
  echo Cannot find project.txt for "%~1"
  popd & exit /b 1
)
set "VBIN=D:\AMDDesignTools\2025.2\Vivado\bin"
if not exist "%ROOT%\vivado" mkdir "%ROOT%\vivado"

echo Creating the Vivado project (about 30 seconds) ...
pushd "%ROOT%\vivado"
call "%VBIN%\vivado.bat" -mode batch -nojournal -nolog -source "%ROOT%\tools\make_vivado_project.tcl" -tclargs "%ROOT%" "%TDIR%" %2
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" (
  echo Could not create the project, see the messages above.
  popd & exit /b %RC%
)

for %%I in ("%TDIR%") do set "NAME=%%~nxI"
echo Opening Vivado ...
pushd "%ROOT%\vivado\%NAME%"
start "" "%VBIN%\vivado.bat" "%NAME%.xpr"
popd
popd
endlocal
