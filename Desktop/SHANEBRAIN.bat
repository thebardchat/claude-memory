@echo off
title SHANEBRAIN — Neural Interface
color 0B
mode con: cols=80 lines=45

:start
cls
echo.
echo   ========================================================================
echo.
echo        ___ _  _   _   _  _ ___ ___ ___    _   ___ _  _
echo       / __^| || ^| /_\ ^| \^| ^| __^| _ ) _ \  /_\ ^|_ _^| \^| ^|
echo       \__ \ __ ^|/ _ \^| .` ^| _^||  _ \   / / _ \ ^| ^|^| .` ^|
echo       ^|___/_^|^|_/_/ \_\_^|\_^|___^|___/_^|_^|/_/ \_\___|_^|\_^|
echo.
echo       Faith . Family . Sobriety . Local AI for the 800M
echo                 Built by Shane Brazelton + Claude AI
echo.
echo   ========================================================================
echo.
echo   [1]  Launch Claude on Pi      (SSH + preflight)     AUTO in 5s
echo   [2]  MEGA Command Center      (full control, no Claude needed)
echo   [3]  Open Dashboard           (browser)
echo   [0]  Exit
echo.
CHOICE /C 1230 /T 5 /D 1 /N /M "  Choice: "
if %errorlevel%==4 goto :exit
if %errorlevel%==3 goto :dashboard
if %errorlevel%==2 goto :commandcenter
goto :claude

:claude
cls
echo.
echo   Connecting to ShaneBrain Pi...
echo   (Tailscale must be running)
echo.
ssh -t shanebrain@shanebrain "bash -i -c 'bash /mnt/shanebrain-raid/shanebrain-core/scripts/preflight.sh && claude'"
echo.
if %ERRORLEVEL% NEQ 0 (
    echo   ERROR: SSH failed. Check that Tailscale is running and Pi is online.
    echo.
    echo   Press any key to return to menu...
    pause >nul
)
goto :start

:commandcenter
PowerShell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MEGA-CommandCenter.ps1"
goto :start

:dashboard
start http://shanebrain:8300
goto :start

:exit
echo.
echo   ShaneBrain -- signing off. Faith. Family. Sobriety.
echo.
timeout /t 2 /nobreak >nul
