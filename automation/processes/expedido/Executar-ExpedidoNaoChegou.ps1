param(
    [string]$UnsealedAt,
    [string]$BaseSigla
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$root = 'C:\oCoffe'
$configPath = Join-Path $root 'config\gestao-kpi.json'
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$logDir = [Environment]::ExpandEnvironmentVariables([string]$config.logDir)
if (-not $logDir) { $logDir = Join-Path $root 'logs' }
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir 'expedido.log'
$exportMetadata = Join-Path $logDir 'expedido-export.json'
$ordersJson = Join-Path $logDir 'expedido-pedidos.json'
$trackingJson = Join-Path $logDir 'expedido-rastreamento.json'
$statusFile = Join-Path $logDir 'expedido-status.json'
function Log([string]$Message) { Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" }
function Set-Status([string]$Stage, [string]$Message, [bool]$Finished = $false, [bool]$Failed = $false) {
    [ordered]@{ updatedAt=(Get-Date).ToString('o'); stage=$Stage; message=$Message; finished=$Finished; failed=$Failed; unsealedAt=$UnsealedAt } |
        ConvertTo-Json | Set-Content -LiteralPath $statusFile -Encoding UTF8
}

try {
    if (-not $BaseSigla) { $BaseSigla = [string]$config.expedidoBaseSigla }
    if (-not $BaseSigla) { throw 'Configure primeiro a sigla da base do líder.' }
    $env:OCOFFE_EXPEDIDO_BASE = $BaseSigla.Trim().ToUpperInvariant()
    if (-not (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables([string]$config.expedidoModeloPlanilha)))) { throw 'Configure primeiro o modelo Excel de Expedido, mas não chegou.' }
    Set-Status 'exportacao' 'Consultando o dia anterior e exportando o JMS.'
    Log "Processo manual iniciado. Deslacramento: $UnsealedAt; base: $env:OCOFFE_EXPEDIDO_BASE."
    & node.exe (Join-Path $root 'browser\jms-expedido-export.js')
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao exportar o monitoramento de tipagem de recebimento.' }
    $metadata = Get-Content -LiteralPath $exportMetadata -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([bool]$metadata.noOrders) {
        Set-Status 'concluido' 'Não existem encomendas para analisar no dia anterior.' $true
        [void][Windows.Forms.MessageBox]::Show('Não existem encomendas para analisar no dia anterior. O processo retornou ao oCoffeIA.', 'Expedido, mas não chegou', 'OK', 'Information')
        return
    }

    Set-Status 'filtro' 'Removendo lotes BR e pedidos filhos/combo.'
    & (Join-Path $root 'processes\expedido\Preparar-PedidosExpedido.ps1') -SourcePath ([string]$metadata.file) -OutputJson $ordersJson
    $prepared = Get-Content -LiteralPath $ordersJson -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$prepared.count -eq 0) {
        Set-Status 'concluido' 'Após os filtros, não restou nenhum pedido para consultar.' $true
        [void][Windows.Forms.MessageBox]::Show('Após retirar lotes BR e pedidos filhos, não restou nenhum pedido. Nenhuma planilha foi criada.', 'Expedido, mas não chegou', 'OK', 'Information')
        return
    }

    Set-Status 'rastreamento' "Consultando $($prepared.count) pedidos em lotes de até 1.000."
    & node.exe (Join-Path $root 'browser\jms-expedido-track.js') $ordersJson
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar o Registro POD dos pedidos.' }

    Set-Status 'planilha' 'Criando a planilha operacional com os pedidos elegíveis.'
    & (Join-Path $root 'processes\expedido\Criar-PlanilhaExpedido.ps1') -TrackingJson $trackingJson
    $result = Get-Content -LiteralPath (Join-Path $logDir 'expedido-resultado.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([bool]$result.noOrders) {
        Set-Status 'concluido' 'Nenhum pedido possui último evento elegível.' $true
        [void][Windows.Forms.MessageBox]::Show('Nenhum pedido está elegível: todos já chegaram, possuem ocorrência ou o último evento não é expedição para a sua base.', 'Expedido, mas não chegou', 'OK', 'Information')
        return
    }
    Set-Status 'concluido' "$($result.count) pedidos salvos. Viagem: $($result.tripId)." $true
    Log "Concluído: $($result.count) pedidos; arquivos: $(@($result.files) -join '; ')."
    [void][Windows.Forms.MessageBox]::Show("Planilha pronta com $($result.count) pedido(s).`r`n`r`n$(@($result.files) -join "`r`n")", 'Expedido, mas não chegou', 'OK', 'Information')
} catch {
    Log "ERRO: $($_.Exception.Message)"
    Set-Status 'erro' $_.Exception.Message $true $true
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Falha — Expedido, mas não chegou', 'OK', 'Error')
    exit 1
}
