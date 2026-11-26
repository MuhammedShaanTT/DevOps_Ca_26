@echo off
setlocal
echo ===================================================
echo  INT333 DevOps - Full Automated Deployment
echo ===================================================

if not exist "%~dp0.env" (
    echo ERROR: .env file not found in "%~dp0"
    echo Copy .env.example to .env and add your AWS credentials first.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\deploy.ps1"
if %errorlevel% neq 0 (
    echo.
    echo Deployment stopped with error code %errorlevel%.
)
pause
