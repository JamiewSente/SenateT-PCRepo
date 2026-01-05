@echo off
:: =========================================================
::  PORTABLE SELF-ELEVATING BUSY-LIGHT LAUNCHER
:: =========================================================

:: --- 0. Pin working directory to this script’s folder ---
cd /d "%~dp0"

:: --- 1. Elevate if not running as admin ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: --- 2. Start Busy-LED server (minimized) ---
set "NODE_EXE=node"
REM If you bundle a portable Node binary in .\node\node.exe, uncomment below:
REM set "NODE_EXE=%~dp0node\node.exe"
start "" /min "%NODE_EXE%" "%~dp0Busy-LED-server.js"

:: --- 3. Open the busy-light HTML page ---
start "" "%~dp0busy-light.html"

:: --- 4. Copy updated Nextiva watcher snippet to clipboard ---
powershell -Command ^
  "Set-Clipboard -Value '(() => { const LED_SERVER = \"http://127.0.0.1:3000\"; let lastLedState = null; function setLed(state) { if (state === lastLedState) return; lastLedState = state; fetch(`${LED_SERVER}/set?state=${state}`, { mode: \"no-cors\" }).catch(() => {}); } function isInCall() { const el = document.querySelector(\".css-kknodv\"); if (!el) return false; const style = window.getComputedStyle(el); const rect = el.getBoundingClientRect(); return style.display !== \"none\" && style.visibility !== \"hidden\" && rect.width > 0 && rect.height > 0; } setLed(isInCall() ? \"on\" : \"off\"); setInterval(() => { setLed(isInCall() ? \"on\" : \"off\"); }, 1000); console.info(\"Busy Light: Watching .css-kknodv visibility with no-cors fetch.\"); })();'"

echo.
echo =========================================================
echo Busy-LED server started (elevated), HTML tool opened.
echo Nextiva watcher snippet has been copied to clipboard.
echo In Nextiva: Press Ctrl+Shift+I → Console → Paste (Ctrl+V) → Enter
echo =========================================================
pause