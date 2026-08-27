param([switch]$Force)

$ErrorActionPreference = 'Stop'
$configFile = 'C:\oCoffe\config\gestao-kpi.json'
$config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
$baseDir = [Environment]::ExpandEnvironmentVariables($(if ($config.slaBaseDir) { [string]$config.slaBaseDir } else { 'C:\Gestão de KPI_Operacional_v2\Base_vencimentos' }))
$pbix = [Environment]::ExpandEnvironmentVariables($(if ($config.powerBi) { [string]$config.powerBi } else { 'C:\Gestão de KPI_Operacional_v2\Gestão de KPI.pbix' }))
$logDir = [Environment]::ExpandEnvironmentVariables($(if ($config.logDir) { [string]$config.logDir } else { 'C:\Gestão de KPI_Operacional_v2\Automacao' }))
$metadataFile = Join-Path $logDir 'ultimo-sla-download.json'
$stateFile = Join-Path $logDir 'ultimo-sla-processado.json'
$logFile = Join-Path $logDir 'sla-atualizacao.log'
New-Item -ItemType Directory -Path $baseDir, $logDir -Force | Out-Null
function Write-SlaLog([string]$Message) { Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" }

if (-not (Test-Path -LiteralPath $metadataFile)) { throw 'Metadados do download diário do SLA não encontrados.' }
$metadata = Get-Content -LiteralPath $metadataFile -Raw -Encoding UTF8 | ConvertFrom-Json
$source = [Environment]::ExpandEnvironmentVariables([string]$metadata.file)
if (-not (Test-Path -LiteralPath $source)) { throw "Arquivo SLA baixado não encontrado: $source" }
$endDate = [datetime]::ParseExact([string]$metadata.endDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
$powerBiDateText = $(if ($metadata.powerBiDate) { [string]$metadata.powerBiDate } else { [string]$metadata.endDate })
$powerBiDate = [datetime]::ParseExact($powerBiDateText, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)

if ((Test-Path -LiteralPath $stateFile) -and -not $Force) {
    $previous = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$previous.executionDate -eq (Get-Date -Format 'yyyy-MM-dd')) {
        Write-SlaLog "SLA já atualizado hoje às $($previous.completedAt); execução repetida ignorada."
        exit 10
    }
}

$item = Get-Item -LiteralPath $source
if ($item.Length -lt 1024) { throw 'O arquivo SLA baixado está vazio ou incompleto.' }
$signature = [IO.File]::ReadAllBytes($source)[0..1]
if ($signature[0] -ne 0x50 -or $signature[1] -ne 0x4B) { throw 'O arquivo SLA não possui estrutura XLSX válida.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($source)
try {
    if (-not $archive.GetEntry('xl/workbook.xml') -or -not $archive.GetEntry('xl/worksheets/sheet1.xml')) {
        throw 'O XLSX do SLA não contém a estrutura esperada.'
    }
} finally { $archive.Dispose() }

$staging = Join-Path $baseDir ('.novo-sla-' + [guid]::NewGuid().ToString('N') + '.xlsx')
Copy-Item -LiteralPath $source -Destination $staging
if ((Get-Item -LiteralPath $staging).Length -ne $item.Length) { throw 'A cópia do SLA ficou incompleta.' }
Get-ChildItem -LiteralPath $baseDir -Filter '*.xlsx' -File | Where-Object FullName -ne $staging | Remove-Item -Force
$destination = Join-Path $baseDir $item.Name
Move-Item -LiteralPath $staging -Destination $destination
Write-SlaLog "Base_vencimentos substituída: $destination"

$pbi = Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object MainWindowTitle -like '*Gestão de KPI*' | Select-Object -First 1
if (-not $pbi) {
    Start-Process -FilePath $pbix
    Start-Sleep -Seconds 25
    $pbi = Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object MainWindowTitle -like '*Gestão de KPI*' | Select-Object -First 1
}
if (-not $pbi) { throw 'O Power BI não abriu dentro do tempo esperado.' }
try { $pbi.PriorityClass = 'BelowNormal' } catch {}

$engine = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'msmdsrv.exe' -and $_.ParentProcessId -eq $pbi.Id } | Select-Object -First 1
if (-not $engine) { throw 'Mecanismo de dados do Power BI não encontrado.' }
$dataPath = [regex]::Match($engine.CommandLine, '-s\s+"([^"]+)"').Groups[1].Value
$port = (Get-Content -LiteralPath (Join-Path $dataPath 'msmdsrv.port.txt') -Encoding Unicode -Raw).Trim([char]0).Trim()
$powerBiBin = Split-Path $pbi.Path
Add-Type -Path (Join-Path $powerBiBin 'Microsoft.AnalysisServices.Server.Core.dll')
Add-Type -Path (Join-Path $powerBiBin 'Microsoft.AnalysisServices.Server.Tabular.dll')
$server = [Microsoft.AnalysisServices.Tabular.Server]::new()
$server.Connect("localhost:$port")
try {
    $model = $server.Databases[0].Model
    $table = $model.Tables.Find('BD_D1')
    if (-not $table) { throw 'Tabela BD_D1 não encontrada no Power BI.' }
    $table.RequestRefresh([Microsoft.AnalysisServices.Tabular.RefreshType]::Full)
    $model.RequestRefresh([Microsoft.AnalysisServices.Tabular.RefreshType]::Calculate)
    $model.SaveChanges()
} finally { $server.Disconnect() }
Write-SlaLog 'Tabela BD_D1 atualizada.'

Add-Type -AssemblyName UIAutomationClient
$pageName = $(if ($config.slaPaginaPowerBi) { [string]$config.slaPaginaPowerBi } else { 'SLA - VENCIMENTO' })
$tab = $null
for ($attempt=0; $attempt -lt 30 -and -not $tab; $attempt++) {
    $root = [Windows.Automation.AutomationElement]::FromHandle($pbi.MainWindowHandle)
    $tabs = $root.FindAll([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::TabItem)))
    for ($i=0; $i -lt $tabs.Count; $i++) {
        if (($tabs.Item($i).Current.Name -replace '^(?:Hidden|Ocult[oa])\s*','') -eq $pageName) { $tab=$tabs.Item($i); break }
    }
    if (-not $tab) { Start-Sleep -Seconds 2 }
}
if (-not $tab) { throw "A página $pageName não foi encontrada após aguardar o carregamento do Power BI." }
$selection=$null; [void]$tab.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$selection); ([Windows.Automation.SelectionItemPattern]$selection).Select()
Start-Sleep -Seconds 3
$dateText = $powerBiDate.ToString('dd/MM/yyyy')
$dateHelper = 'C:\oCoffe\tools\PowerBI-DateRange.ps1'
if (-not (Test-Path -LiteralPath $dateHelper)) { throw "Componente de datas não encontrado: $dateHelper" }
. $dateHelper
$verifiedDates = Set-PowerBIDateRangeVerified -WindowHandle $pbi.MainWindowHandle -Date $powerBiDate -Context 'SLA'
Write-SlaLog "Filtros do SLA verificados: início $($verifiedDates.Start), final $($verifiedDates.End)."
Start-Sleep -Seconds 2
$shell=New-Object -ComObject WScript.Shell
[void]$shell.AppActivate($pbi.Id); $shell.SendKeys('^s')
$state=[ordered]@{executionDate=Get-Date -Format 'yyyy-MM-dd';completedAt=(Get-Date).ToString('o');endDate=$metadata.endDate;powerBiDate=$powerBiDateText;file=$destination}
$state|ConvertTo-Json|Set-Content -LiteralPath $stateFile -Encoding UTF8
Write-SlaLog "SLA concluído para a data final $dateText."
