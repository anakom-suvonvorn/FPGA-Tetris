@echo off
rem ===========================================================================
rem  program.bat  -  load a .bit file into the board (temporary, like the
rem                  Builder's "Normal Rom"). Uses the Builder's openFPGALoader.
rem
rem  Usage:   tools\program.bat 01_vga_bars
rem           tools\program.bat 01_vga_bars flash    (permanent: writes the SPI
rem                                                   flash, like "PROM Rom")
rem           tools\program.bat path\to\any_file.bit (e.g. one made in the Vivado GUI)
rem  Close FPGA Builder first if it is open, they share the USB cable.
rem ===========================================================================
setlocal
rem a .bit file given directly? (checked before the pushd below changes folder)
set "BIT="
if /i "%~x1"==".bit" if exist "%~f1" set "BIT=%~f1"
set "ROOT=%~dp0.."
pushd "%ROOT%"
set "ROOT=%CD%"
set "OFL=D:\setup\FPGA_Builder_Package_V9\tools\openFPGALoader\openFPGALoader.exe"
set "SPI=D:\setup\FPGA_Builder_Package_V9\tools\openFPGALoader\spiOverJtag_xc7s15ftgb196.bit"

set "TDIR=%ROOT%\tests\%~1"
if not exist "%TDIR%\build" set "TDIR=%ROOT%\%~1"
if "%BIT%"=="" for %%F in ("%TDIR%\build\*.bit") do set "BIT=%%F"
if "%BIT%"=="" (
  echo No .bit file in %TDIR%\build - run tools\build.bat %~1 first.
  popd & exit /b 1
)
set "PATH=D:\setup\FPGA_Builder_Package_V9\tools\openFPGALoader;%PATH%"
if /i "%~2"=="flash" (
  echo Writing %BIT% to the board's flash ^(permanent^) ...
  "%OFL%" -c ft2232 -f -B "%SPI%" "%BIT%"
) else (
  echo Loading %BIT% into the FPGA ^(temporary^) ...
  "%OFL%" -c ft2232 -m "%BIT%"
)
popd
endlocal
