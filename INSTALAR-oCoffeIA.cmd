@echo off
setlocal
cd /d "%~dp0"
title Instalador do oCoffeIA
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Windows.Forms; $texto='O oCoffeIA precisa de autorizacao para verificar e instalar os componentes necessarios nesta maquina:' + [Environment]::NewLine + [Environment]::NewLine + '- Node.js LTS' + [Environment]::NewLine + '- Google Chrome' + [Environment]::NewLine + '- Power BI Desktop' + [Environment]::NewLine + '- Extensao Playwright' + [Environment]::NewLine + [Environment]::NewLine + 'Tambem serao criados o atalho e as tarefas de atualizacao.' + [Environment]::NewLine + [Environment]::NewLine + 'Deseja autorizar e continuar?'; $resposta=[System.Windows.Forms.MessageBox]::Show($texto,'Autorizacao para instalar o oCoffeIA',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question); if($resposta -ne [System.Windows.Forms.DialogResult]::Yes){exit 2}"
if errorlevel 1 (
  echo Instalacao cancelada pelo usuario.
  exit /b 2
)
fltmc >nul 2>&1
if errorlevel 1 (
  echo Solicitando permissao de administrador...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
echo Preparando o oCoffeIA e seus componentes...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0automation\install\Bootstrap-oCoffe.ps1"
if errorlevel 1 (
  echo.
  echo A instalacao nao foi concluida. Leia a mensagem acima.
  pause
  exit /b 1
)
echo.
echo Instalacao concluida. Use o atalho oCoffeIA na Area de Trabalho.
pause
