param([switch]$NoReview)

$ErrorActionPreference = 'Stop'
$root = 'C:\oCoffe'
$configFile = Join-Path $root 'config\gestao-kpi.json'
$reportDir = Join-Path $root 'reports'
$logFile = Join-Path $root 'desempenho.log'
$reviewScript = Join-Path $root 'processes\desempenho\Revisar-AlertaDesempenho.ps1'

function Write-PerformanceLog([string]$Message) {
    Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
}

function Normalize-Header([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $normalized = $Value.Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object Text.StringBuilder
    foreach ($character in $normalized.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    return (($builder.ToString().Normalize([Text.NormalizationForm]::FormC)) -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
}

function Convert-ExcelDate($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    if ($Value -is [double] -or $Value -is [int]) {
        try { return [datetime]::FromOADate([double]$Value) } catch { return $null }
    }
    $parsed = [datetime]::MinValue
    foreach ($culture in @([Globalization.CultureInfo]::InvariantCulture, [Globalization.CultureInfo]::GetCultureInfo('pt-BR'))) {
        if ([datetime]::TryParse([string]$Value, $culture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsed)) { return $parsed }
    }
    return $null
}

try {
    if (-not (Test-Path -LiteralPath $configFile)) { throw 'Configuração local não encontrada.' }
    $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($config.PSObject.Properties['alertaDesempenhoAtivo'] -and -not [bool]$config.alertaDesempenhoAtivo) {
        Write-PerformanceLog 'Análise desativada na configuração.'
        exit 0
    }

    $baseDir = [Environment]::ExpandEnvironmentVariables([string]$config.baseDir)
    $source = Get-ChildItem -LiteralPath $baseDir -Filter '*.xlsx' -File -ErrorAction Stop |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $source) { throw "Nenhum XLSX encontrado em $baseDir" }

    $minimumPercent = if ($config.alertaPercentualMinimo) { [double]$config.alertaPercentualMinimo } else { 100 }
    $minimumHours = if ($config.alertaMinimoHorasRota) { [double]$config.alertaMinimoHorasRota } else { 6 }
    $minimumOrders = if ($config.alertaMinimoPedidos) { [int]$config.alertaMinimoPedidos } else { 10 }

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    try {
        $workbook = $excel.Workbooks.Open($source.FullName, 0, $true)
        $sheet = $workbook.Worksheets.Item(1)
        $range = $sheet.UsedRange
        $values = $range.Value2
        $headers = @{}
        for ($column = 1; $column -le $range.Columns.Count; $column++) {
            $key = Normalize-Header ([string]$values[1, $column])
            if ($key -and -not $headers.ContainsKey($key)) { $headers[$key] = $column }
        }
        $courierColumn = $headers['responsavelpelaentrega']
        $signatureColumn = $headers['marcadeassinatura']
        $departureColumn = $headers['horariodesaidaparaentrega']
        if (-not $courierColumn -or -not $signatureColumn -or -not $departureColumn) {
            throw 'O relatório não contém as colunas necessárias para analisar responsável, assinatura e saída da rota.'
        }

        $routes = @{}
        for ($row = 2; $row -le $range.Rows.Count; $row++) {
            $courier = ([string]$values[$row, $courierColumn]).Trim()
            if (-not $courier) { continue }
            if (-not $routes.ContainsKey($courier)) {
                $routes[$courier] = [ordered]@{ Courier = $courier; Total = 0; Delivered = 0; Departure = $null }
            }
            $route = $routes[$courier]
            $route.Total++
            $signature = ([string]$values[$row, $signatureColumn]).Trim()
            if ($signature -and $signature -notmatch '(?i)não entregue|nao entregue|devolu') { $route.Delivered++ }
            $departure = Convert-ExcelDate $values[$row, $departureColumn]
            if ($departure -and (-not $route.Departure -or $departure -lt $route.Departure)) { $route.Departure = $departure }
        }
    } finally {
        if ($workbook) { $workbook.Close($false) }
        $excel.Quit()
        if ($range) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($range) }
        if ($sheet) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sheet) }
        if ($workbook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }

    $now = Get-Date
    $alerts = foreach ($route in $routes.Values) {
        if (-not $route.Departure -or $route.Total -lt $minimumOrders) { continue }
        $hours = ($now - [datetime]$route.Departure).TotalHours
        if ($hours -lt $minimumHours -or $hours -lt 0) { continue }
        $percent = if ($route.Total) { [math]::Round(($route.Delivered * 100.0) / $route.Total, 2) } else { 0 }
        if ($percent -lt $minimumPercent) {
            [pscustomobject]@{
                entregador = $route.Courier
                saida = ([datetime]$route.Departure).ToString('dd/MM/yyyy HH:mm')
                horasDeRota = [math]::Round($hours, 1)
                pedidos = $route.Total
                entregues = $route.Delivered
                percentual = $percent
            }
        }
    }
    $alerts = @($alerts | Sort-Object percentual, horasDeRota)

    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    $resultFile = Join-Path $reportDir 'alerta-desempenho.json'
    $result = [ordered]@{
        generatedAt = $now.ToString('o')
        sourceFile = $source.FullName
        whatsappResponsavel = [string]$config.whatsappResponsavel
        regra = [ordered]@{ percentualMinimo = $minimumPercent; minimoHorasRota = $minimumHours; minimoPedidos = $minimumOrders }
        alertas = $alerts
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultFile -Encoding UTF8
    Write-PerformanceLog "Análise concluída: $($alerts.Count) entregador(es) abaixo da regra. Fonte: $($source.Name)"

    if ($alerts.Count -gt 0 -and -not $NoReview -and $config.whatsappResponsavel -and (Test-Path -LiteralPath $reviewScript)) {
        $arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$reviewScript`" -ResultPath `"$resultFile`""
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $arguments
    }
    exit 0
} catch {
    Write-PerformanceLog "ERRO: $($_.Exception.Message)"
    exit 1
}

