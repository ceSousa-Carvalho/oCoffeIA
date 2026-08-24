param(
    [string]$Destino = 'C:\oCoffe',
    [string]$ProjetoKpi = 'C:\Gestão de KPI_Operacional_v2'
)

$ErrorActionPreference = 'Stop'
$installScript = Join-Path $PSScriptRoot 'Install-oCoffe.ps1'

function Write-Step([string]$Text) {
    Write-Host "`n==> $Text" -ForegroundColor Cyan
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machinePath, $userPath) -join ';'
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$Source = 'winget',
        [string]$Label = $Id
    )

    Write-Step "Instalando $Label"
    $arguments = @(
        'install', '--id', $Id, '--exact', '--source', $Source,
        '--accept-package-agreements', '--accept-source-agreements',
        '--silent', '--disable-interactivity'
    )
    & winget.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível instalar $Label pelo winget (código $LASTEXITCODE)."
    }
    Refresh-ProcessPath
}

Write-Host 'INSTALADOR COMPLETO DO oCoffeIA' -ForegroundColor Green
Write-Host 'Este assistente verifica e instala os componentes obrigatórios.'

if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'O Gerenciador de Pacotes do Windows (winget/App Installer) não está disponível. Atualize o Windows ou instale o App Installer pela Microsoft Store.'
}

Refresh-ProcessPath

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    Install-WingetPackage -Id 'OpenJS.NodeJS.LTS' -Label 'Node.js LTS'
}
if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    $nodeCandidate = 'C:\Program Files\nodejs\node.exe'
    if (Test-Path -LiteralPath $nodeCandidate) {
        $env:Path = "$(Split-Path $nodeCandidate);$env:Path"
    } else {
        throw 'Node.js foi instalado, mas o executável não foi localizado.'
    }
}

$chromeCandidates = @(
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
)
if (-not ($chromeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)) {
    Install-WingetPackage -Id 'Google.Chrome' -Label 'Google Chrome'
}

$powerBiCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\PBIDesktop.exe'),
    'C:\Program Files\Microsoft Power BI Desktop RS\bin\PBIDesktop.exe'
)
$powerBiProcess = Get-Process PBIDesktop -ErrorAction SilentlyContinue | Select-Object -First 1
$powerBiAppx = Get-AppxPackage -Name 'Microsoft.MicrosoftPowerBIDesktop' -ErrorAction SilentlyContinue
$powerBiInstalled = [bool]$powerBiProcess -or [bool]$powerBiAppx -or
    [bool](Get-Command PBIDesktop.exe -ErrorAction SilentlyContinue) -or
    [bool]($powerBiCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
if (-not $powerBiInstalled) {
    Install-WingetPackage -Id '9NTXR16HNW1T' -Source 'msstore' -Label 'Power BI Desktop'
}

$targetPbix = Join-Path $ProjetoKpi 'Gestão de KPI.pbix'
$bundledPbix = Join-Path (Split-Path -Parent $PSScriptRoot) 'templates\Gestão de KPI.pbix'
if (-not (Test-Path -LiteralPath $targetPbix) -and -not (Test-Path -LiteralPath $bundledPbix)) {
    Write-Step 'Localizando o relatório do Power BI'
    Write-Warning 'O arquivo PBIX contém dados da empresa e não foi incluído automaticamente no pacote.'
    $pbixInformado = Read-Host 'Informe o caminho completo do arquivo Gestão de KPI.pbix'
    $pbixInformado = $pbixInformado.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $pbixInformado -PathType Leaf) -or [IO.Path]::GetExtension($pbixInformado) -ne '.pbix') {
        throw 'Arquivo PBIX inválido. Selecione o relatório Gestão de KPI.pbix para concluir.'
    }
    New-Item -ItemType Directory -Path $ProjetoKpi -Force | Out-Null
    Copy-Item -LiteralPath $pbixInformado -Destination $targetPbix -Force
}

Write-Step 'Instalando o oCoffeIA e as dependências do navegador'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -Destino $Destino -ProjetoKpi $ProjetoKpi
if ($LASTEXITCODE -ne 0) { throw "A instalação do oCoffeIA terminou com código $LASTEXITCODE." }

$excelAvailable = $null -ne (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe' -ErrorAction SilentlyContinue)
$feishuAvailable = [bool](Get-Command Feishu.exe -ErrorAction SilentlyContinue)

Write-Host "`nVERIFICAÇÃO FINAL" -ForegroundColor Cyan
Write-Host "Node.js: $(& node.exe --version)"
Write-Host 'Google Chrome: instalado'
Write-Host 'Power BI Desktop: instalado ou provisionado pela Microsoft Store'
Write-Host 'Playwright: instalado'
if (-not $excelAvailable) {
    Write-Warning 'Microsoft Excel não foi encontrado. Ele é opcional e necessário apenas para alguns relatórios de desempenho/expedido.'
}
if (-not $feishuAvailable) {
    Write-Warning 'Feishu não foi encontrado. Ele é opcional e necessário apenas para o envio de SLA ao Feishu.'
}
Write-Host "`noCoffeIA pronto para uso." -ForegroundColor Green
