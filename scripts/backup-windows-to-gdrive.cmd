@echo off
:: backup-windows-to-gdrive.cmd
::
:: Pre-wipe insurance backup for Shane's Windows nodes.
:: Uploads user folders (Documents, Desktop, Downloads, Pictures, Videos, Music)
:: to Google Drive under: gdrive:claude-memory-backups/<hostname>/
::
:: Prereqs (one-time, see docs/BACKUP-AND-WIPE.md):
::   1. Install rclone:    https://rclone.org/install/
::   2. Configure remote:  rclone config   (name it "gdrive", auth as brazeltonshane@gmail.com)
::
:: Usage (in cmd, on the Windows node being decommissioned):
::   cd %USERPROFILE%\claude-memory\scripts
::   backup-windows-to-gdrive.cmd
::
:: This script does NOT delete anything. It only uploads.
:: When the upload finishes cleanly (errorlevel 0), proceed with the wipe per
:: docs/NODE-WIPE-LINUX.md.

setlocal EnableDelayedExpansion

set REMOTE=gdrive
set BUCKET=claude-memory-backups
set DEST=%REMOTE%:%BUCKET%/%COMPUTERNAME%

echo === Pre-flight checks ===

where rclone >nul 2>nul
if errorlevel 1 (
  echo [FAIL] rclone is not on PATH.
  echo        Install: https://rclone.org/install/
  echo        Then run: rclone config  to set up remote "gdrive".
  echo        See docs\BACKUP-AND-WIPE.md for step-by-step.
  exit /b 1
)

rclone listremotes | findstr /B /C:"%REMOTE%:" >nul
if errorlevel 1 (
  echo [FAIL] rclone remote "%REMOTE%" is not configured.
  echo        Run: rclone config
  echo        Create a remote named "gdrive" of type "drive".
  echo        Authenticate as brazeltonshane@gmail.com.
  exit /b 1
)

rclone ls "%REMOTE%:" >nul 2>nul
if errorlevel 1 (
  echo [FAIL] Cannot reach Google Drive on remote "%REMOTE%".
  echo        Re-auth: rclone config reconnect "%REMOTE%":
  exit /b 1
)

echo [OK]   rclone present, remote configured, Google Drive reachable.
echo.

echo === Backup target ===
echo Hostname:    %COMPUTERNAME%
echo User:        %USERNAME%
echo Source:      %USERPROFILE%
echo Destination: %DEST%
echo.

set FOLDERS=Documents Desktop Downloads Pictures Videos Music

for %%D in (%FOLDERS%) do (
  if exist "%USERPROFILE%\%%D" (
    echo === Uploading %%D ===
    rclone copy --progress --transfers 4 --checkers 8 ^
      --exclude ".cache/**" ^
      --exclude "*.tmp" ^
      --exclude "Thumbs.db" ^
      --exclude "desktop.ini" ^
      "%USERPROFILE%\%%D" "%DEST%/%%D/"
    if errorlevel 1 (
      echo [FAIL] Upload of %%D failed. DO NOT WIPE THIS NODE.
      exit /b 1
    )
    echo [OK]   %%D uploaded.
    echo.
  ) else (
    echo [SKIP] %USERPROFILE%\%%D does not exist.
    echo.
  )
)

echo === Writing manifest ===
set MANIFEST=%TEMP%\backup-manifest-%COMPUTERNAME%.txt
echo Hostname: %COMPUTERNAME% > "%MANIFEST%"
echo User: %USERNAME% >> "%MANIFEST%"
echo Backed up: %date% %time% >> "%MANIFEST%"
echo Source: %USERPROFILE% >> "%MANIFEST%"
echo Destination: %DEST% >> "%MANIFEST%"
echo. >> "%MANIFEST%"
echo === System info === >> "%MANIFEST%"
systeminfo | findstr /B /C:"OS Name" /C:"OS Version" /C:"System Manufacturer" /C:"System Model" /C:"Total Physical Memory" >> "%MANIFEST%"
echo. >> "%MANIFEST%"
echo === Network === >> "%MANIFEST%"
ipconfig | findstr /C:"IPv4" >> "%MANIFEST%"
echo. >> "%MANIFEST%"
echo === Tailscale === >> "%MANIFEST%"
tailscale status 2>nul | findstr /B /V "#" >> "%MANIFEST%"

rclone copyto "%MANIFEST%" "%DEST%/manifest.txt"
if errorlevel 1 (
  echo [WARN] Manifest upload failed, but data backup succeeded.
)

echo.
echo === DONE ===
echo Backed up: %COMPUTERNAME% to %DEST%
echo.
echo Verify the upload:
echo   rclone ls "%DEST%/"
echo.
echo Then proceed with the wipe per docs\NODE-WIPE-LINUX.md
echo (only after verifying you can browse the backup in Google Drive web UI).

endlocal
