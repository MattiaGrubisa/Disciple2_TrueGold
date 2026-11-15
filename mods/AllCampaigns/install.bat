@echo off
rem Runs install.ps1 without needing to change the PowerShell execution policy.
rem PSModulePath is cleared so Windows PowerShell uses its own modules, even when this is
rem started from PowerShell 7 (whose module path would otherwise be inherited).
setlocal
set "PSModulePath="
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
