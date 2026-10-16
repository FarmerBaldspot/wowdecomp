@echo off
rem Ours (the World of Warcraft editor project): builds bin\Win\WowClient64.exe. Double-click it.
cd /d "%~dp0"

tasklist /fi "imagename eq WowClient64.exe" | find /i "WowClient64.exe" >nul
if not errorlevel 1 (
    echo The client is running. Close it first, then run this again.
    pause
    exit /b 1
)

if not exist "build\x64\CMakeCache.txt" (
    echo Setting the build up, once...
    "C:\Program Files\CMake\bin\cmake.exe" -S . -B build\x64 -G "Visual Studio 17 2022" -A x64 -DWOWDECOMP_DISABLE_SIGNATURE_CHECKS=ON
    if errorlevel 1 goto failed
)

echo Building the client...
"C:\Program Files\CMake\bin\cmake.exe" --build build\x64 --config Release --target WowClient --parallel
if errorlevel 1 goto failed

echo.
echo Done: bin\Win\WowClient64.exe
pause
exit /b 0

:failed
echo.
echo The build FAILED. The lines above say why.
pause
exit /b 1
