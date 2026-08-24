$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$reportDir = 'C:\oCoffe\reports'
$logFile = 'C:\oCoffe\whatsapp.log'
$reviewScript = 'C:\oCoffe\processes\whatsapp\Revisar-EnvioWhatsApp.ps1'
$baseDir = 'C:\Gestão de KPI_Operacional_v2\Base_Gestão_de_pedidos_'
$reportPage = 'D+0 - RESUMIDO'
$configFile = 'C:\oCoffe\config\gestao-kpi.json'
if (Test-Path -LiteralPath $configFile) {
    $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace($config.baseDir)) { $baseDir = [Environment]::ExpandEnvironmentVariables([string]$config.baseDir) }
    if (-not [string]::IsNullOrWhiteSpace($config.paginaPowerBi)) { $reportPage = [string]$config.paginaPowerBi }
}

New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$powerBi = Get-Process PBIDesktop -ErrorAction Stop |
    Where-Object { $_.MainWindowTitle -like '*Gestão de KPI*' } |
    Select-Object -First 1
if (-not $powerBi) { throw 'Janela Gestão de KPI não encontrada.' }

function Select-PowerBIPage([IntPtr]$WindowHandle, [string]$PageName) {
    Add-Type -AssemblyName UIAutomationClient
    $root = [Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
    $tabCondition = New-Object Windows.Automation.PropertyCondition(
        [Windows.Automation.AutomationElement]::ControlTypeProperty,
        [Windows.Automation.ControlType]::TabItem
    )
    $tabs = $root.FindAll([Windows.Automation.TreeScope]::Descendants, $tabCondition)
    $normalize = {
        param([string]$Value)
        (($Value -replace '^(?:Hidden|Ocult[oa])\s*', '') -replace '\s+', '').ToUpperInvariant()
    }
    $target = & $normalize $PageName
    $selectedTab = $null
    for ($index = 0; $index -lt $tabs.Count; $index++) {
        $tab = $tabs.Item($index)
        if ((& $normalize $tab.Current.Name) -eq $target) {
            $selectedTab = $tab
            break
        }
    }
    if (-not $selectedTab) {
        throw "A aba '$PageName' não foi encontrada no Power BI."
    }
    $pattern = $null
    if (-not $selectedTab.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
        throw "A aba '$PageName' foi encontrada, mas não pôde ser selecionada."
    }
    ([Windows.Automation.SelectionItemPattern]$pattern).Select()
}

$captureSource = @'
using System;
using System.Runtime.InteropServices;
public static class oCoffeCapture {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
}
'@
Add-Type -TypeDefinition $captureSource

[oCoffeCapture]::ShowWindow($powerBi.MainWindowHandle, 3) | Out-Null
[oCoffeCapture]::SetForegroundWindow($powerBi.MainWindowHandle) | Out-Null
Start-Sleep -Seconds 2
Select-PowerBIPage -WindowHandle $powerBi.MainWindowHandle -PageName $reportPage
Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Aba selecionada para captura: $reportPage"
Start-Sleep -Seconds 3
$rect = New-Object oCoffeCapture+RECT
if (-not [oCoffeCapture]::GetWindowRect($powerBi.MainWindowHandle, [ref]$rect)) {
    throw 'Não foi possível obter a área da janela do Power BI.'
}
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
$latestReport = Get-ChildItem -LiteralPath $baseDir -Filter '*.xlsx' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$reportTime = if ($latestReport) { $latestReport.LastWriteTime } else { Get-Date }
$dateHelper = 'C:\oCoffe\tools\PowerBI-DateRange.ps1'
if (-not (Test-Path -LiteralPath $dateHelper)) { throw "Componente de datas não encontrado: $dateHelper" }
. $dateHelper
$verifiedDates = Set-PowerBIDateRangeVerified -WindowHandle $powerBi.MainWindowHandle -Date $reportTime.Date -Context 'acompanhamento dos entregadores'
Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Filtros verificados antes da captura: início $($verifiedDates.Start), final $($verifiedDates.End)."
$image = Join-Path $reportDir ("parcial-{0}.png" -f $reportTime.ToString('yyyyMMdd-HHmmss'))
$bitmap = [Drawing.Bitmap]::new($width, $height)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
    $hdc = $graphics.GetHdc()
    try {
        $captured = [oCoffeCapture]::PrintWindow($powerBi.MainWindowHandle, $hdc, 2)
    } finally {
        $graphics.ReleaseHdc($hdc)
    }
    if (-not $captured) {
        throw 'O Windows não permitiu capturar diretamente a janela do Power BI.'
    }
    # Recorta somente a página do relatório: remove faixa de opções, navegação,
    # painéis de edição, abas e barra de status. As proporções funcionam em
    # diferentes resoluções quando o Power BI está maximizado.
    $cropLeft = [int][Math]::Round($bitmap.Width * 0.043)
    $cropTop = [int][Math]::Round($bitmap.Height * 0.202)
    $cropRight = [int][Math]::Round($bitmap.Width * 0.720)
    $cropBottom = [int][Math]::Round($bitmap.Height * 0.915)
    $reportArea = [Drawing.Rectangle]::FromLTRB($cropLeft, $cropTop, $cropRight, $cropBottom)
    $cropped = $bitmap.Clone($reportArea, $bitmap.PixelFormat)
    try {
        $cropped.Save($image, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $cropped.Dispose()
    }
} finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

if (-not (Test-Path -LiteralPath $reviewScript)) { throw "Tela de revisão não encontrada: $reviewScript" }
$metadata = [ordered]@{
    reportTime = $reportTime.ToString('o')
    reportFile = if ($latestReport) { $latestReport.FullName } else { $null }
    imagePath = $image
    powerBiPage = $reportPage
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath ([IO.Path]::ChangeExtension($image, '.json')) -Encoding UTF8
$reviewArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$reviewScript`" -ImagePath `"$image`" -ReportTime `"$($reportTime.ToString('o'))`""
Start-Process -FilePath powershell.exe -ArgumentList $reviewArgs
Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Captura criada para o relatório baixado às $($reportTime.ToString('HH:mm')); aguardando confirmação: $image"









