@echo off
setlocal
cd /d "%~dp0"
title Desinstalador do oCoffeIA
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0automation\install\Uninstall-oCoffe.ps1"
pause
