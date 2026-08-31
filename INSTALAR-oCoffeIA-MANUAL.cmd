@echo off
setlocal
cd /d "%~dp0"
title Instalador do oCoffeIA - Modo Manual
fltmc >nul 2>&1
if errorlevel 1 (
  echo Solicitando permissao de administrador...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
echo Preparando o oCoffeIA em modo manual...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0automation\install\Bootstrap-oCoffe.ps1" -ManualOnly
if errorlevel 1 (
  echo.
  echo A instalacao nao foi concluida. Leia a mensagem acima.
  pause
  exit /b 1
)
echo.
echo Instalacao manual concluida. Nenhuma rotina sera executada por horario.
pause
