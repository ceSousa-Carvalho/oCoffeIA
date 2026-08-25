param(
    [Parameter(Mandatory = $true)]
    [string]$Arquivo
)

$ErrorActionPreference = 'Stop'
$root = 'C:\oCoffe'
$configFile = Join-Path $root 'config\gestao-kpi.json'
$updateScript = Join-Path $root 'processes\gestao-kpi\Atualizar-GestaoKPI.ps1'
$captureScript = Join-Path $root 'processes\whatsapp\Capturar-e-Enviar.ps1'
$logFile = Join-Path $root 'ocoffe.log'

function Write-ManualLog([string]$Message) {
    Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Power BI manual: $Message"
}

try {
    $source = Get-Item -LiteralPath $Arquivo -ErrorAction Stop
    if ($source.Extension -ne '.xlsx' -or $source.Length -lt 1024) {
        throw 'Selecione uma planilha XLSX válida exportada pelo JMS.'
    }

    $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $downloads = [Environment]::ExpandEnvironmentVariables([string]$config.downloads)
    if ([string]::IsNullOrWhiteSpace($downloads)) { $downloads = Join-Path $env:USERPROFILE 'Downloads' }
    New-Item -ItemType Directory -Path $downloads -Force | Out-Null

    # Cria uma entrada nova para o atualizador sem alterar o arquivo escolhido.
    $manualFile = Join-Path $downloads ("Exportar carta de porte de entrega-manual-{0}.xlsx" -f (Get-Date -Format 'yyyyMMddHHmmss'))
    Copy-Item -LiteralPath $source.FullName -Destination $manualFile

    Write-ManualLog "planilha selecionada: $($source.FullName)"

    & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $updateScript
    if ($LASTEXITCODE -ne 0) { throw "A atualização do Power BI terminou com código $LASTEXITCODE." }

    & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $captureScript
    if ($LASTEXITCODE -ne 0) { throw "A captura da parcial terminou com código $LASTEXITCODE." }
    Write-ManualLog 'fluxo concluído; revisão aberta para confirmação.'
} catch {
    Write-ManualLog "ERRO: $($_.Exception.Message)"
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.MessageBox]::Show(
        "Não foi possível gerar a parcial manual.`r`n`r`n$($_.Exception.Message)",
        'oCoffeIA | Power BI manual',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}
