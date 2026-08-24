$ErrorActionPreference = 'Stop'

$root = 'C:\oCoffe'
$node = (Get-Command node.exe -ErrorAction Stop).Source
$browserScript = Join-Path $root 'browser\jms-download.js'
$updateScript = Join-Path $root 'processes\gestao-kpi\Atualizar-GestaoKPI.ps1'
$captureScript = Join-Path $root 'processes\whatsapp\Capturar-e-Enviar.ps1'
$performanceScript = Join-Path $root 'processes\desempenho\Analisar-Desempenho.ps1'
$logFile = 'C:\oCoffe\ocoffe.log'
$stateFile = Join-Path $root 'reports\estado-atualizacao.json'

function Write-oCoffeLog([string]$Message) {
    Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
}

function Set-UpdateState([string]$Stage, [string]$Status, [string]$Detail = '') {
    New-Item -ItemType Directory -Path (Split-Path $stateFile) -Force | Out-Null
    [ordered]@{ updatedAt=(Get-Date).ToString('o'); stage=$Stage; status=$Status; detail=$Detail; processId=$PID } |
        ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
}

function Invoke-WithRetry([string]$Label, [scriptblock]$Action, [int]$Attempts = 3) {
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Set-UpdateState $Label 'executando' "tentativa $attempt de $Attempts"
        Write-oCoffeLog "${Label}: tentativa $attempt de $Attempts."
        & $Action
        if ($LASTEXITCODE -eq 0) { return }
        if ($attempt -lt $Attempts) {
            Write-oCoffeLog "$Label falhou com código $LASTEXITCODE; nova tentativa em 10 segundos."
            Start-Sleep -Seconds 10
        }
    }
    throw "$Label falhou após $Attempts tentativas."
}

$executionMutex = [Threading.Mutex]::new($false, 'Global\oCoffeIA-Atualizacao-Principal')
$ownsExecutionMutex = $false
$exitCode = 0
try {
    Set-UpdateState 'fila' 'aguardando' 'aguardando a execução anterior terminar'
    try { $ownsExecutionMutex = $executionMutex.WaitOne([TimeSpan]::FromMinutes(30)) } catch [Threading.AbandonedMutexException] { $ownsExecutionMutex = $true }
    if (-not $ownsExecutionMutex) {
        Write-oCoffeLog 'Execução cancelada: a fila permaneceu ocupada por mais de 30 minutos.'
        Set-UpdateState 'fila' 'erro' 'tempo máximo de espera excedido'
        exit 2
    }

    Write-oCoffeLog 'Iniciando consulta e download do JMS.'
    Invoke-WithRetry 'JMS / download' { & $node $browserScript }

    Write-oCoffeLog 'Download confirmado. Iniciando atualização do Power BI.'
    Invoke-WithRetry 'Power BI' { & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $updateScript }

    Write-oCoffeLog 'Power BI atualizado. Criando a parcial para revisão do usuário.'
    Invoke-WithRetry 'Captura da parcial' { & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $captureScript } 2

    if (Test-Path -LiteralPath $performanceScript) {
        Write-oCoffeLog 'Analisando o desempenho das rotas para alertas ao responsável.'
        & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $performanceScript
        if ($LASTEXITCODE -ne 0) { Write-oCoffeLog "AVISO: análise de desempenho terminou com código $LASTEXITCODE." }
    }

    Write-oCoffeLog 'Fluxo concluído. Aguardando confirmação do usuário antes de qualquer reporte.'
    Set-UpdateState 'revisão WhatsApp' 'aguardando confirmação' 'print gerado com sucesso'
} catch {
    Write-oCoffeLog "ERRO: $($_.Exception.Message)"
    Set-UpdateState 'fluxo' 'erro' $_.Exception.Message
    $exitCode = 1
} finally {
    if ($ownsExecutionMutex) { $executionMutex.ReleaseMutex() }
    $executionMutex.Dispose()
}

exit $exitCode







