$ErrorActionPreference = 'Stop'

$pbix = 'C:\Gestão de KPI_Operacional_v2\Gestão de KPI.pbix'
$backupDir = 'C:\Gestão de KPI_Operacional_v2\Automacao\backup-pbix'
$powerBiBin = (Get-Process PBIDesktop -ErrorAction Stop | Select-Object -First 1).Path | Split-Path
$workspace = Get-CimInstance Win32_Process |
    Where-Object { $_.Name -eq 'msmdsrv.exe' -and $_.CommandLine -match 'AnalysisServicesWorkspace_' } |
    Select-Object -First 1
if (-not $workspace) { throw 'O mecanismo interno do Power BI não está em execução.' }
$dataPath = [regex]::Match($workspace.CommandLine, '-s\s+"([^"]+)"').Groups[1].Value
$portFile = Join-Path (Split-Path $dataPath) 'Data\msmdsrv.port.txt'
$port = (Get-Content -LiteralPath $portFile -Encoding Unicode -Raw).Trim([char]0).Trim()

New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$backup = Join-Path $backupDir ("Gestão de KPI-{0}.pbix" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Copy-Item -LiteralPath $pbix -Destination $backup

$mBody = @'
let
    Fonte = Excel.Workbook(ARQUIVO_BINARIO, null, true),
    Abas = Table.SelectRows(Fonte, each [Kind] = "Sheet" or [Kind] = "Table"),
    Dados = if Table.RowCount(Abas) > 0 then Abas{0}[Data] else error "Nenhuma aba encontrada no relatório JMS.",
    Cabecalhos = Table.PromoteHeaders(Dados, [PromoteAllScalars=true]),
    Mapeamento = {
        {"运单编号", "Número de pedido JMS"},
        {"派件网点", "Base de entrega"},
        {"派件业务员", "Responsável pela entrega"},
        {"派件时间", "Tempo de entrega"},
        {"签收标识", "Marca de assinatura"},
        {"签收网点", "PDD de Entrega"},
        {"签收时间", "Horário da entrega"},
        {"结算方式", "Prazo de Vencimento"},
        {"创建时间", "Data de criação"},
        {"始发地", "Origem"},
        {"派件网点编码", "Código da base de entrega"},
        {"三段码", "3 Segmentos"},
        {"派件业务员编码", "Código entregador"},
        {"寄件州", "Estado Remetente"},
        {"寄件城市", "Cidade de Origem"},
        {"收件人", "Destinatário"},
        {"收件人手机号", "Celular do Destinatário"},
        {"收件人座机", "Tel fixo do destinatário"},
        {"收件州", "UF Destino"},
        {"收件城市", "Cidade Destino"},
        {"收件区域", "Distrito destinatário"},
        {"收件详细地址", "Complemento"},
        {"签收网点编码", "Código da base de entrega_1"},
        {"审核时间", "Tempo de aprovação"},
        {"审核人", "Revisor"},
        {"问题件标识", "Marca de pacote problemático"},
        {"问题件原因", "Motivos dos pacotes problemáticos"},
        {"商务件标识", "Marca de pacote comercial"},
        {"转退件标识", "Marca de transferência e devolução"},
        {"算费描述", "Descrição de cálculo de taxa"},
        {"备注", "Observação"},
        {"数据来源", "Origem de dados"},
        {"更新时间", "Tempo de atualização"},
        {"始发邮编", "CEP de origem"},
        {"目的邮编", "CEP destino"},
        {"是否合单", "Pedido unificado?"},
        {"税号", "CNPJ"}
    },
    ColunasTraduzidas = Table.RenameColumns(Cabecalhos, Mapeamento, MissingField.Ignore),
    ColunasProduto = if List.Contains(Table.ColumnNames(ColunasTraduzidas), "Tipo de produto")
        then Table.RenameColumns(ColunasTraduzidas, {{"Tipo de produto", "Tipo de Produto.1"}}, MissingField.Ignore)
        else ColunasTraduzidas
in
    ColunasProduto
'@

$sampleExpression = $mBody.Replace('ARQUIVO_BINARIO', 'Parâmetro9')
$functionBody = $mBody.Replace('ARQUIVO_BINARIO', 'Parâmetro9')
$functionExpression = "let`n    Fonte = (Parâmetro9 as binary) => $functionBody`nin`n    Fonte"

Add-Type -Path (Join-Path $powerBiBin 'Microsoft.AnalysisServices.Server.Core.dll')
Add-Type -Path (Join-Path $powerBiBin 'Microsoft.AnalysisServices.Server.Tabular.dll')
$server = [Microsoft.AnalysisServices.Tabular.Server]::new()
$server.Connect("localhost:$port")
try {
    $model = $server.Databases[0].Model
    $sample = $model.Expressions.Find('Transformar o Arquivo de Exemplo (9)')
    $function = $model.Expressions.Find('Transformar Arquivo (9)')
    if (-not $sample -or -not $function) { throw 'As consultas auxiliares da Gestão de Pedidos não foram encontradas.' }
    $sample.Expression = $sampleExpression
    $function.Expression = $functionExpression
    $model.SaveChanges()
} finally {
    $server.Disconnect()
}

$shell = New-Object -ComObject WScript.Shell
$shell.AppActivate('Gestão de KPI') | Out-Null
Start-Sleep -Seconds 2
$shell.SendKeys('^s')
Start-Sleep -Seconds 5

Write-Output "Consulta alterada. Backup: $backup"





