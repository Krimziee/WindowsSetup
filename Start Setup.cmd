@echo off
setlocal
title Windows Setup - Launcher

rem ------------------------------------------------------------------
rem  Copies the tool to C:\WindowsSetup and starts it with admin rights.
rem  Running from a local copy avoids two problems:
rem    - an elevated (admin) process can't see network drive letters
rem    - shared folders / USB sticks may be read-only
rem ------------------------------------------------------------------

set "SOURCE=%~dp0"
set "TARGET=C:\WindowsSetup"

if /i "%SOURCE%"=="%TARGET%\" goto :launch

echo Copying Windows Setup to %TARGET% ...
robocopy "%SOURCE:~0,-1%" "%TARGET%" /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1 >nul
if %ERRORLEVEL% GEQ 8 (
    echo.
    echo Could not copy the files to %TARGET%.
    echo Try running "Start Setup.cmd" again, or copy the folder there yourself.
    pause
    exit /b 1
)

:launch
echo Starting Windows Setup - click "Yes" on the admin prompt.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File','%TARGET%\setup.ps1'"
if errorlevel 1 (
    echo.
    echo Setup needs admin rights to run. Start it again and click "Yes".
    pause
    exit /b 1
)
exit /b 0
