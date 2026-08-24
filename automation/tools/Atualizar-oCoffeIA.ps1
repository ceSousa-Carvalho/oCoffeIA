param([switch]$Force)

$ErrorActionPreference = 'Stop'
$root = 'C:\oCoffe'
$configFile = Join-Path $root 'config\gestao-kpi.json'
$versionUrl = 'https://raw.githubusercontent.com/ceSousa-Carvalho/oCoffeIA/main/VERSAO-oCoffeIA.txt'
$archiveUrl = 'https://github.com/ceSousa-Carvalho/oCoffeIA/archive/refs/heads/main.zip'

if (-not (Test-Path -LiteralPath $configFile)) { throw 'Configuração instalada não encontrada.' }
$config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
$current = [version]([string]$config.versao)
$versionDocument = Invoke-RestMethod -Uri $versionUrl -TimeoutSec 20
$availableText = [regex]::Match([string]$versionDocument, '\d+\.\d+\.\d+').Value
if (-not $availableText) { throw 'Não foi possível identificar a versão publicada.' }
$available = [version]$availableText
if (-not $Force -and $available -le $current) { Write-Host "oCoffeIA já está atualizado ($current)." -ForegroundColor Green; exit 0 }

$temp = Join-Path ([IO.Path]::GetTempPath()) ("ocoffe-update-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    $zip = Join-Path $temp 'ocoffe.zip'
    Invoke-WebRequest -Uri $archiveUrl -OutFile $zip -TimeoutSec 120
    Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
    $source = Get-ChildItem -LiteralPath $temp -Directory | Where-Object Name -like 'oCoffeIA-*' | Select-Object -First 1
    if (-not $source) { throw 'Pacote baixado do GitHub é inválido.' }
    $automation = Join-Path $source.FullName 'automation'
    if (-not (Test-Path -LiteralPath (Join-Path $automation 'Executar-oCoffe.ps1'))) { throw 'Automação não encontrada no pacote.' }
    Get-ChildItem -LiteralPath $automation -Force | Where-Object Name -ne 'browser' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $root -Recurse -Force }
    Copy-Item -Path (Join-Path $automation 'browser\*') -Destination (Join-Path $root 'browser') -Recurse -Force
    Push-Location (Join-Path $root 'browser')
    try { & npm.cmd install --omit=dev; if($LASTEXITCODE -ne 0){throw 'Falha ao restaurar dependências do navegador.'} } finally { Pop-Location }
    $config.versao = $availableText
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configFile -Encoding UTF8
    Write-Host "oCoffeIA atualizado para $availableText. Configurações e logins preservados." -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
