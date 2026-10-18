@echo off
rem ===========================================================================
rem  build.bat  -  build one design into a .bit file, with timing report
rem
rem  Usage (from a Command Prompt in the assignment folder):
rem      tools\build.bat 01_vga_bars
rem  or double-click build_all.bat to build every test.
rem
rem  Result: tests\<name>\build\<top>.bit   (+ timing.txt, utilization.txt, vivado.log)
rem  Load the .bit with FPGA Builder ("Program") or tools\program.bat.
rem  Takes about 1-2 minutes. Keep the laptop plugged in.
rem ===========================================================================
setlocal
set "ROOT=%~dp0.."
pushd "%ROOT%"
set "ROOT=%CD%"

if "%~1"=="" (
  echo Usage: tools\build.bat ^<design folder name^>   e.g. tools\build.bat 01_vga_bars
  popd & exit /b 1
)
set "TDIR=%ROOT%\tests\%~1"
if not exist "%TDIR%\project.txt" set "TDIR=%ROOT%\%~1"
if not exist "%TDIR%\project.txt" (
  echo Cannot find project.txt for "%~1"
  popd & exit /b 1
)

rem Prefer the full Vivado install, fall back to the copy inside FPGA Builder.
set "VIVADO=D:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat"
if not exist "%VIVADO%" set "VIVADO=D:\setup\FPGA_Builder_Package_V9\tools\vivado_min\2025.2\Vivado\bin\vivado.bat"

if not exist "%TDIR%\build" mkdir "%TDIR%\build"
echo Building %TDIR% ...
rem run Vivado inside the build folder so its scratch files stay there
pushd "%TDIR%\build"
call "%VIVADO%" -mode batch -nojournal -log "%TDIR%\build\vivado.log" -source "%ROOT%\tools\build_test.tcl" -tclargs "%ROOT%" "%TDIR%"
set "RC=%ERRORLEVEL%"
popd
popd
if not "%RC%"=="0" (
  echo.
  echo BUILD FAILED - read the first ERROR line in %TDIR%\build\vivado.log
  exit /b %RC%
)
echo.
echo Done. Bitstream is in %TDIR%\build
endlocal
