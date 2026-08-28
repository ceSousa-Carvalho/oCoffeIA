param(
    [Parameter(Mandatory = $true)]
    [string]$Arquivo,

    [Parameter(Mandatory = $true)]
    [string]$DataFinal
)

$ErrorActionPreference = 'Stop'
$root = 'C:\oCoffe'
$configFile = Join-Path $root 'config\gestao-kpi.json'
$updateScript = Join-Path $root 'processes\sla\Atualizar-SLA.ps1'
$logFile = Join-Path $root 'sla.log'

function Write-ManualSlaLog([string]$Message) {
    Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') SLA manual: $Message"
}

try {
    $source = Get-Item -LiteralPath $Arquivo -ErrorAction Stop
    if ($source.Extension -ne '.xlsx' -or $source.Length -lt 1024) {
        throw 'Selecione uma planilha XLSX válida de Entrega realizada (Lista).'
    }
    $endDate = [datetime]::ParseExact($DataFinal, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($source.FullName)
    try {
        $entry = $archive.GetEntry('xl/workbook.xml')
        if (-not $entry) { throw 'A planilha não possui uma estrutura XLSX válida.' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $workbookXml = $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($workbookXml -notmatch 'name="sheet0"') {
            throw 'A aba esperada não foi encontrada. O arquivo do SLA deve possuir a aba sheet0.'
        }
    } finally {
        $archive.Dispose()
    }

    $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $historyDays = [int]$(if ($config.slaDiasHistorico) { $config.slaDiasHistorico } else { 27 })
    $logDir = [Environment]::ExpandEnvironmentVariables($(if ($config.logDir) { [string]$config.logDir } else { 'C:\Gestão de KPI_Operacional_v2\Automacao' }))
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    $metadata = [ordered]@{
        file = $source.FullName
        startDate = $endDate.AddDays(-$historyDays).ToString('yyyy-MM-dd')
        endDate = $endDate.ToString('yyyy-MM-dd')
        downloadedAt = (Get-Date).ToString('o')
        manual = $true
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logDir 'ultimo-sla-download.json') -Encoding UTF8
    Write-ManualSlaLog "planilha selecionada: $($source.FullName); data final: $DataFinal"

    & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $updateScript -Force
    if ($LASTEXITCODE -ne 0) { throw "A atualização da tabela BD_D1 terminou com código $LASTEXITCODE." }

    Write-ManualSlaLog 'fluxo concluído; Power BI atualizado e salvo.'
} catch {
    Write-ManualSlaLog "ERRO: $($_.Exception.Message)"
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.MessageBox]::Show(
        "Não foi possível atualizar o SLA manualmente.`r`n`r`n$($_.Exception.Message)",
        'oCoffeIA | SLA manual',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}
