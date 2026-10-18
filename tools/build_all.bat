@echo off
rem Builds every design in the tests folder, one after another.
pushd "%~dp0.."
for /d %%D in (tests\*) do (
  if exist "%%D\project.txt" call tools\build.bat %%~nxD
)
popd
pause
