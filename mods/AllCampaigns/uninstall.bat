@echo off
rem Runs uninstall.ps1 without needing to change the PowerShell execution policy.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
pause
