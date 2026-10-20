@echo off
rem ===========================================================================
rem  flash_media.bat  -  write a media file (make_game_media.py) into the
rem                      board's SPI flash, 1 MB in (address 0x100000).
rem
rem  Usage:   tools\flash_media.bat media\game_media.bin   (the game's media)
rem           tools\flash_media.bat media\media.bin        (test 06's demo file)
rem           tools\flash_media.bat check media\media.bin
rem                (reads the first 64 KB back out of the flash and compares)
rem
rem  The flash also holds the FPGA's own start-up bitstream at address 0
rem  (about 0.5 MB, only if you ever used "PROM"/flash programming). This
rem  writes from 1 MB on, so that stays untouched.
rem  Writing loads a small helper design ("spiOverJtag") into the FPGA first;
rem  afterwards load your design again (tools\program.bat game, or 06_flash_read).
rem  Close FPGA Builder first if it is open, they share the USB cable.
rem ===========================================================================
setlocal
set "OFL=D:\setup\FPGA_Builder_Package_V9\tools\openFPGALoader\openFPGALoader.exe"
set "SPI=D:\setup\FPGA_Builder_Package_V9\tools\openFPGALoader\spiOverJtag_xc7s15ftgb196.bit"
set "PATH=D:\setup\FPGA_Builder_Package_V9\tools\openFPGALoader;%PATH%"

if /i "%~1"=="check" goto :check
if "%~1"=="" (
  echo Usage: tools\flash_media.bat media\media.bin
  exit /b 1
)
if not exist "%~f1" (
  echo No such file: %~1   - make it first: python tools\make_game_media.py   ^(or tools\make_media.py ... --demo^)
  exit /b 1
)
echo Writing %~f1 into the flash at 0x100000 ...
"%OFL%" -c ft2232 -f -B "%SPI%" -o 0x100000 "%~f1"
if errorlevel 1 (
  echo FAILED - see the messages above
  exit /b 1
)
echo Done. Now load your design again: tools\program.bat game   (or 06_flash_read)
exit /b 0

:check
if not exist "%~f2" (
  echo Usage: tools\flash_media.bat check media\media.bin
  exit /b 1
)
echo Reading 64 KB back from the flash at 0x100000 ...
"%OFL%" -c ft2232 -B "%SPI%" --dump-flash -o 0x100000 --file-size 65536 "%TEMP%\flash_dump.bin"
if errorlevel 1 (
  echo FAILED - see the messages above
  exit /b 1
)
python -c "import sys; a=open(sys.argv[1],'rb').read(65536); b=open(sys.argv[2],'rb').read(65536); n=min(len(a),len(b)); bad=sum(1 for i in range(n) if a[i]!=b[i]); print('read back', len(b), 'bytes,', bad, 'differ from the file' + ('  -> FLASH CONTENTS OK' if bad==0 else '')); print('first bytes in flash:', b[:8].hex(' '))" "%~f2" "%TEMP%\flash_dump.bin"
exit /b 0
