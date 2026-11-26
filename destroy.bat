@echo off
setlocal
echo ===================================================
echo  INT333 DevOps - Tear Down AWS Infrastructure
echo ===================================================

if not exist "%~dp0.env" (
    echo ERROR: .env file not found in "%~dp0"
    echo Copy .env.example to .env and add your AWS credentials first.
    pause
    exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in (`findstr /r /c:"^[^#;][^=]*=" "%~dp0.env"`) do (
    set "%%A=%%B"
)

cd /d "%~dp0terraform"
if %errorlevel% neq 0 (
    pause
    exit /b %errorlevel%
)

terraform destroy -auto-approve
pause
