param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$OutputJson
)

$ErrorActionPreference = 'Stop'
$excel = $null
$workbook = $null
try {
    if (-not (Test-Path -LiteralPath $SourcePath)) { throw "Planilha exportada não encontrada: $SourcePath" }
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $workbook = $excel.Workbooks.Open($SourcePath, 0, $true)
    $sheet = $workbook.Worksheets.Item(1)
    $used = $sheet.UsedRange
    $orders = [Collections.Generic.List[string]]::new()
    for ($row = 2; $row -le $used.Rows.Count; $row++) {
        $value = [string]$sheet.Cells.Item($row, 1).Text
        $value = $value.Trim()
        if (-not $value) { continue }
        if ($value -match '^(?i:BR)') { continue }
        if ($value -match '-\d+$') { continue }
        if ($orders -notcontains $value) { $orders.Add($value) }
    }
    $parent = Split-Path -Parent $OutputJson
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [ordered]@{
        source = $SourcePath
        generatedAt = (Get-Date).ToString('o')
        count = $orders.Count
        orders = @($orders)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputJson -Encoding UTF8
} finally {
    if ($workbook) { $workbook.Close($false) }
    if ($excel) { $excel.Quit() }
    foreach ($item in @($used, $sheet, $workbook, $excel)) {
        if ($item) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($item) }
    }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
