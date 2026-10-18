@echo off
rem Fill FPGA Builder with one of our designs (close FPGA Builder first!).
rem Usage: tools\load_into_builder.bat 01_vga_bars   (or double-click and type the name)
setlocal
set "NAME=%~1"
if "%NAME%"=="" (
  echo Designs:
  for /d %%D in ("%~dp0..\tests\*") do echo    %%~nxD
  set /p NAME=Which design?
)
python "%~dp0load_into_builder.py" %NAME%
pause
