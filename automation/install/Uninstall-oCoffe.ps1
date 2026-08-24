param(
    [string]$Destino = 'C:\oCoffe'
)

$ErrorActionPreference = 'Stop'

Unregister-ScheduledTask -TaskName 'JMS - Atualizar Gestão KPI' -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'JMS - Atualizar SLA' -Confirm:$false -ErrorAction SilentlyContinue

$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'oCoffeIA.lnk'
if (Test-Path -LiteralPath $desktopShortcut) {
    Remove-Item -LiteralPath $desktopShortcut -Force
}

$cliPath = Join-Path $Destino 'cli'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not [string]::IsNullOrWhiteSpace($userPath)) {
    $newPath = (($userPath -split ';') | Where-Object { $_ -and $_ -ne $cliPath }) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
}

Write-Host 'A tarefa horária do oCoffe foi removida.' -ForegroundColor Yellow
Write-Host 'O atalho e o comando ocoffe foram removidos.'
Write-Host "Os arquivos e dados em $Destino foram preservados para recuperação manual."






