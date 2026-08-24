$ErrorActionPreference = 'Stop'

$root = 'C:\oCoffe'
$node = (Get-Command node.exe -ErrorAction Stop).Source
$browserScript = Join-Path $root 'browser\jms-download.js'
$updateScript = Join-Path $root 'processes\gestao-kpi\Atualizar-GestaoKPI.ps1'
$captureScript = Join-Path $root 'processes\whatsapp\Capturar-e-Enviar.ps1'
$performanceScript = Join-Path $root 'processes\desempenho\Analisar-Desempenho.ps1'
$logFile = 'C:\oCoffe\ocoffe.log'

function Write-oCoffeLog([string]$Message) {
    Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
}

$executionMutex = [Threading.Mutex]::new($false, 'Global\oCoffeIA-Atualizacao-Principal')
$ownsExecutionMutex = $false
$exitCode = 0
try {
    try { $ownsExecutionMutex = $executionMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsExecutionMutex = $true }
    if (-not $ownsExecutionMutex) {
        Write-oCoffeLog 'Execução ignorada: já existe uma atualização em andamento.'
        exit 2
    }

    Write-oCoffeLog 'Iniciando consulta e download do JMS.'
    & $node $browserScript
    if ($LASTEXITCODE -ne 0) {
        throw "O navegador do JMS terminou com código $LASTEXITCODE."
    }

    Write-oCoffeLog 'Download confirmado. Iniciando atualização do Power BI.'
    & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $updateScript
    if ($LASTEXITCODE -ne 0) {
        throw "A atualização do Power BI terminou com código $LASTEXITCODE."
    }

    Write-oCoffeLog 'Power BI atualizado. Criando a parcial para revisão do usuário.'
    & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $captureScript
    if ($LASTEXITCODE -ne 0) {
        throw "A captura da parcial terminou com código $LASTEXITCODE."
    }

    if (Test-Path -LiteralPath $performanceScript) {
        Write-oCoffeLog 'Analisando o desempenho das rotas para alertas ao responsável.'
        & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $performanceScript
        if ($LASTEXITCODE -ne 0) { Write-oCoffeLog "AVISO: análise de desempenho terminou com código $LASTEXITCODE." }
    }

    Write-oCoffeLog 'Fluxo concluído. Aguardando confirmação do usuário antes de qualquer reporte.'
} catch {
    Write-oCoffeLog "ERRO: $($_.Exception.Message)"
    $exitCode = 1
} finally {
    if ($ownsExecutionMutex) { $executionMutex.ReleaseMutex() }
    $executionMutex.Dispose()
}

exit $exitCode







