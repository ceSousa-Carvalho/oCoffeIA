param(
    [Parameter(Mandatory)][string]$TrackingJson,
    [string]$TemplatePath,
    [string]$OutputDirectory,
    [int]$MaximumRowsPerFile = 500
)

$ErrorActionPreference = 'Stop'
$configPath = 'C:\oCoffe\config\gestao-kpi.json'
$config = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $TemplatePath) { $TemplatePath = [Environment]::ExpandEnvironmentVariables([string]$config.expedidoModeloPlanilha) }
if (-not $OutputDirectory) { $OutputDirectory = [Environment]::ExpandEnvironmentVariables([string]$config.expedidoPastaSaida) }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $env:USERPROFILE 'Downloads\oCoffe-Expedido-nao-chegou' }
if (-not (Test-Path -LiteralPath $TrackingJson)) { throw "Resultado do rastreamento não encontrado: $TrackingJson" }
if (-not (Test-Path -LiteralPath $TemplatePath)) { throw "Modelo Excel não encontrado: $TemplatePath" }

$tracking = Get-Content -LiteralPath $TrackingJson -Raw -Encoding UTF8 | ConvertFrom-Json
$orders = @($tracking.validOrders | ForEach-Object { [string]$_ } | Where-Object { $_ })
if ($orders.Count -eq 0) {
    [ordered]@{ generatedAt=(Get-Date).ToString('o'); noOrders=$true; files=@(); count=0 } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $TrackingJson) 'expedido-resultado.json') -Encoding UTF8
    return
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$tripId = ([string]$tracking.firstTripId -replace '[^A-Za-z0-9_-]', '_')
if (-not $tripId) { $tripId = 'SEM_ID_VIAGEM' }
$chunks = [math]::Ceiling($orders.Count / [double]$MaximumRowsPerFile)
$files = [Collections.Generic.List[string]]::new()

for ($part = 0; $part -lt $chunks; $part++) {
    $start = $part * $MaximumRowsPerFile
    $end = [math]::Min($orders.Count - 1, $start + $MaximumRowsPerFile - 1)
    $current = @($orders[$start..$end])
    $suffix = if ($chunks -gt 1) { "_parte_$($part + 1)" } else { '' }
    $destination = Join-Path $OutputDirectory "Expedido_nao_chegou_${tripId}${suffix}.xlsx"
    Copy-Item -LiteralPath $TemplatePath -Destination $destination -Force

    $excel = $null; $workbook = $null; $sheet = $null; $used = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $workbook = $excel.Workbooks.Open($destination)
        $sheet = $workbook.Worksheets.Item(1)
        $headers = @('Número da carta de porte', 'tipo de operação', 'Primeiro nível codificação', 'Nível II codificação', 'causa do problema')
        for ($column = 1; $column -le 5; $column++) { $sheet.Cells.Item(1, $column).Value2 = $headers[$column - 1] }

        $used = $sheet.UsedRange
        $lastExisting = [math]::Max(2, $used.Row + $used.Rows.Count - 1)
        $sheet.Range("A2:E$lastExisting").ClearContents()
        $sheet.Columns('B:E').Interior.Pattern = -4142
        $sheet.Range("A2:A$($current.Count + 1)").NumberFormat = '@'
        foreach ($index in 0..($current.Count - 1)) {
            $row = $index + 2
            $sheet.Cells.Item($row, 1).Value2 = [string]$current[$index]
            $sheet.Cells.Item($row, 2).Value2 = 'Transit'
            $sheet.Cells.Item($row, 3).Value2 = 'N00'
            $sheet.Cells.Item($row, 4).Value2 = 'N29a'
            $chineseSuffix = ([char]0x6709) + ([char]0x53D1) + ([char]0x672A) + ([char]0x5230) + ([char]0x4EF6)
            $sheet.Cells.Item($row, 5).Value2 = "Encomenda.expedido.mas.não.chegou.$chineseSuffix"
        }
        $lastDataRow = $current.Count + 1
        $sheet.Range("B1:E$lastDataRow").Interior.ColorIndex = 6
        if ($lastExisting -gt $lastDataRow) {
            $sheet.Range("A$($lastDataRow + 1):E$lastExisting").Clear()
            [void]$sheet.Rows("$($lastDataRow + 1):$lastExisting").Delete()
        }
        $workbook.Save()
        $files.Add($destination)
    } finally {
        if ($workbook) { $workbook.Close($true) }
        if ($excel) { $excel.Quit() }
        foreach ($item in @($used, $sheet, $workbook, $excel)) {
            if ($item) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($item) }
        }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
}

[ordered]@{
    generatedAt = (Get-Date).ToString('o')
    noOrders = $false
    tripId = $tripId
    count = $orders.Count
    files = @($files)
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $TrackingJson) 'expedido-resultado.json') -Encoding UTF8
