@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================================
echo REMOVE ONLY THE BOTTOM RELEASE-SECURITY TEXT
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\PATCH-REMOVE-EXACT-RELEASE-BLOCK.ps1"
if errorlevel 1 (
    echo.
    echo Cleanup failed. The homepage was not changed or was restored.
    pause
    exit /b 1
)

echo.
pause
