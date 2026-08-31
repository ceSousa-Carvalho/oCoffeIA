param(
    [string]$Destino = 'C:\oCoffe',
    [string]$ProjetoKpi = 'C:\Gestão de KPI_Operacional_v2',
    [switch]$ManualOnly
)

$ErrorActionPreference = 'Stop'

function Grant-LocalUsersConfigAccess([string]$Path) {
    # Use o SID do grupo interno Usuários para funcionar em Windows em qualquer
    # idioma e também quando outro administrador fornece as credenciais do UAC.
    $identity = New-Object Security.Principal.SecurityIdentifier([Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)

    $acl = Get-Acl -LiteralPath $Path
    $rights = [Security.AccessControl.FileSystemRights]::Modify
    $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, $rights, $inheritance, $propagation, 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

$origem = Split-Path -Parent $PSScriptRoot
$processoOrigem = Join-Path $origem 'processes\gestao-kpi\Atualizar-GestaoKPI.ps1'
$processoDestinoDir = Join-Path $Destino 'processes\gestao-kpi'
$processoDestino = Join-Path $processoDestinoDir 'Atualizar-GestaoKPI.ps1'
$whatsappOrigem = Join-Path $origem 'processes\whatsapp'
$whatsappDestino = Join-Path $Destino 'processes\whatsapp'
$slaOrigem = Join-Path $origem 'processes\sla'
$slaDestino = Join-Path $Destino 'processes\sla'
$feishuOrigem = Join-Path $origem 'processes\feishu'
$feishuDestino = Join-Path $Destino 'processes\feishu'
$desempenhoOrigem = Join-Path $origem 'processes\desempenho'
$desempenhoDestino = Join-Path $Destino 'processes\desempenho'
$expedidoOrigem = Join-Path $origem 'processes\expedido'
$expedidoDestino = Join-Path $Destino 'processes\expedido'
$configDir = Join-Path $Destino 'config'
$configFile = Join-Path $configDir 'gestao-kpi.json'
$cliOrigem = Join-Path $origem 'cli'
$cliDestino = Join-Path $Destino 'cli'
$uiOrigem = Join-Path $origem 'ui'
$uiDestino = Join-Path $Destino 'ui'
$toolsOrigem = Join-Path $origem 'tools'
$toolsDestino = Join-Path $Destino 'tools'
$templatesOrigem = Join-Path $origem 'templates'
$templatesDestino = Join-Path $Destino 'templates'
$pbixOrigem = Join-Path $templatesOrigem 'Gestão de KPI.pbix'
$browserOrigem = Join-Path $origem 'browser'
$browserDestino = Join-Path $Destino 'browser'
$orquestradorOrigem = Join-Path $origem 'Executar-oCoffe.ps1'
$orquestradorDestino = Join-Path $Destino 'Executar-oCoffe.ps1'
$manualPowerBiOrigem = Join-Path $origem 'Executar-PowerBI-Manual.ps1'
$manualPowerBiDestino = Join-Path $Destino 'Executar-PowerBI-Manual.ps1'
$manualSlaOrigem = Join-Path $origem 'Executar-SLA-Manual.ps1'
$manualSlaDestino = Join-Path $Destino 'Executar-SLA-Manual.ps1'
$orquestradorSlaOrigem = Join-Path $origem 'Executar-SLA.ps1'
$orquestradorSlaDestino = Join-Path $Destino 'Executar-SLA.ps1'
$existingConfig = if (Test-Path -LiteralPath $configFile) {
    Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
} else { [pscustomobject]@{} }

if (-not (Test-Path -LiteralPath $processoOrigem)) {
    throw "Script do processo não encontrado: $processoOrigem"
}

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    throw 'Node.js não encontrado. Instale o Node.js antes de continuar.'
}
$chromeCandidates = @(
    [string]$existingConfig.chrome,
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$chromeDetectado = $chromeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $chromeDetectado) {
    throw 'Google Chrome não encontrado. Instale o Chrome antes de continuar.'
}
$edgeCandidates = @(
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
)
$edgeDetectado = $edgeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $edgeDetectado) { $edgeDetectado = $chromeDetectado }

New-Item -ItemType Directory -Path $processoDestinoDir, $whatsappDestino, $slaDestino, $feishuDestino, $desempenhoDestino, $expedidoDestino, $configDir, $cliDestino, $uiDestino, $browserDestino, $toolsDestino, $templatesDestino -Force | Out-Null
$processoConteudo = Get-Content -LiteralPath $processoOrigem -Raw -Encoding UTF8
Set-Content -LiteralPath $processoDestino -Value $processoConteudo -Encoding UTF8
Copy-Item -Path (Join-Path $whatsappOrigem '*') -Destination $whatsappDestino -Recurse -Force
Copy-Item -Path (Join-Path $slaOrigem '*') -Destination $slaDestino -Recurse -Force
Copy-Item -Path (Join-Path $feishuOrigem '*') -Destination $feishuDestino -Recurse -Force
Copy-Item -Path (Join-Path $desempenhoOrigem '*') -Destination $desempenhoDestino -Recurse -Force
Get-ChildItem -LiteralPath $expedidoOrigem -Filter '*.ps1' -File | ForEach-Object {
    $content = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $expedidoDestino $_.Name) -Value $content -Encoding UTF8
}
Copy-Item -Path (Join-Path $browserOrigem '*') -Destination $browserDestino -Recurse -Force
if (-not (Test-Path -LiteralPath (Join-Path $browserDestino 'node_modules\playwright-core'))) {
    Push-Location $browserDestino
    try {
        & npm.cmd install --omit=dev
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao instalar o componente de automação do navegador.' }
    } finally {
        Pop-Location
    }
}
$orquestradorConteudo = Get-Content -LiteralPath $orquestradorOrigem -Raw -Encoding UTF8
Set-Content -LiteralPath $orquestradorDestino -Value $orquestradorConteudo -Encoding UTF8
if (Test-Path -LiteralPath $manualPowerBiOrigem) {
    $manualPowerBiConteudo = Get-Content -LiteralPath $manualPowerBiOrigem -Raw -Encoding UTF8
    Set-Content -LiteralPath $manualPowerBiDestino -Value $manualPowerBiConteudo -Encoding UTF8
}
if (Test-Path -LiteralPath $manualSlaOrigem) {
    $manualSlaConteudo = Get-Content -LiteralPath $manualSlaOrigem -Raw -Encoding UTF8
    Set-Content -LiteralPath $manualSlaDestino -Value $manualSlaConteudo -Encoding UTF8
}
$orquestradorSlaConteudo = Get-Content -LiteralPath $orquestradorSlaOrigem -Raw -Encoding UTF8
Set-Content -LiteralPath $orquestradorSlaDestino -Value $orquestradorSlaConteudo -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $cliOrigem 'ocoffe.cmd') -Destination $cliDestino -Force
$cliConteudo = Get-Content -LiteralPath (Join-Path $cliOrigem 'ocoffe.ps1') -Raw -Encoding UTF8
Set-Content -LiteralPath (Join-Path $cliDestino 'ocoffe.ps1') -Value $cliConteudo -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $uiOrigem 'oCoffeIA.cmd') -Destination $uiDestino -Force
$uiConteudo = Get-Content -LiteralPath (Join-Path $uiOrigem 'oCoffeIA.ps1') -Raw -Encoding UTF8
Set-Content -LiteralPath (Join-Path $uiDestino 'oCoffeIA.ps1') -Value $uiConteudo -Encoding UTF8
if (Test-Path -LiteralPath $toolsOrigem) {
    Copy-Item -Path (Join-Path $toolsOrigem '*') -Destination $toolsDestino -Recurse -Force
}
if (Test-Path -LiteralPath $templatesOrigem) {
    Copy-Item -Path (Join-Path $templatesOrigem '*') -Destination $templatesDestino -Recurse -Force
}

$powerBiProjeto = Join-Path $ProjetoKpi 'Gestão de KPI.pbix'
if (-not (Test-Path -LiteralPath $powerBiProjeto) -and (Test-Path -LiteralPath $pbixOrigem)) {
    New-Item -ItemType Directory -Path $ProjetoKpi -Force | Out-Null
    Copy-Item -LiteralPath $pbixOrigem -Destination $powerBiProjeto -Force
}

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutShell = New-Object -ComObject WScript.Shell
$shortcut = $shortcutShell.CreateShortcut((Join-Path $desktop 'oCoffeIA.lnk'))
$shortcut.TargetPath = Join-Path $uiDestino 'oCoffeIA.cmd'
$shortcut.WorkingDirectory = $uiDestino
$shortcut.Description = 'Abrir o assistente oCoffeIA'
$shortcut.Save()

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $cliDestino) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $cliDestino } else { "$userPath;$cliDestino" }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
}

Write-Host ''
Write-Host 'CONFIGURAÇÃO INICIAL DO oCoffeIA' -ForegroundColor Cyan
$linkPrompt = if ($existingConfig.grupoWhatsApp) { 'Link do grupo WhatsApp (Enter para preservar o atual)' } else { 'Cole o link do grupo do WhatsApp' }
$grupoInformado = Read-Host $linkPrompt
$grupoWhatsApp = if ([string]::IsNullOrWhiteSpace($grupoInformado)) { [string]$existingConfig.grupoWhatsApp } else { $grupoInformado.Trim() }
if ($grupoWhatsApp -notmatch '^https://chat\.whatsapp\.com/[A-Za-z0-9_-]+/?$') {
    throw 'Link inválido. Informe um endereço no formato https://chat.whatsapp.com/CODIGO'
}

$nomePadrao = if ($existingConfig.nomeGrupoWhatsApp) { [string]$existingConfig.nomeGrupoWhatsApp } else { 'Entregadores J&T - THE' }
$nomeInformado = Read-Host "Nome exato do grupo WhatsApp [$nomePadrao]"
$nomeGrupo = if ([string]::IsNullOrWhiteSpace($nomeInformado)) { $nomePadrao } else { $nomeInformado.Trim() }

$horariosAtuais = @($existingConfig.horariosAtualizacao) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
$horarios = if ($ManualOnly) { @() } else { @($horariosAtuais) }
if (-not $ManualOnly) {
    $textoAtual = if ($horariosAtuais.Count -gt 0) { $horariosAtuais -join ', ' } else { 'sem execução automática' }
    $horariosInformados = Read-Host "Horários diários, separados por vírgula (Enter para $textoAtual)"
}
if (-not $ManualOnly -and -not [string]::IsNullOrWhiteSpace($horariosInformados)) {
    $horarios = @()
    $horariosInformados = $horariosInformados.Trim().Trim('(', ')')
    foreach ($item in ($horariosInformados -split '[,;\s]+' | Where-Object { $_ })) {
        if ($item -notmatch '^(?:[01]?\d|2[0-3]):[0-5]\d$') { throw "Horário inválido: $item. Use HH:mm." }
        $normalizado = ([datetime]::ParseExact($item.PadLeft(5, '0'), 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)).ToString('HH:mm')
        if ($horarios -notcontains $normalizado) { $horarios += $normalizado }
    }
    $horarios = @($horarios | Sort-Object)
}

$whatsResponsavelAtual = if ($existingConfig.whatsappResponsavel) { [string]$existingConfig.whatsappResponsavel } else { '' }
$whatsResponsavelInformado = Read-Host "WhatsApp do responsável para alertas, com DDD [$whatsResponsavelAtual]"
$whatsappResponsavel = if ([string]::IsNullOrWhiteSpace($whatsResponsavelInformado)) { $whatsResponsavelAtual } else { $whatsResponsavelInformado }
$whatsappResponsavel = $whatsappResponsavel -replace '\D', ''
if ($whatsappResponsavel.Length -in 10, 11) { $whatsappResponsavel = "55$whatsappResponsavel" }
if ($whatsappResponsavel -and $whatsappResponsavel -notmatch '^\d{12,13}$') {
    throw 'WhatsApp inválido. Informe DDD + número; por exemplo, 86999999999.'
}

$baseDir = Join-Path $ProjetoKpi 'Base_Gestão_de_pedidos_'
$powerBi = Join-Path $ProjetoKpi 'Gestão de KPI.pbix'
$logDir = Join-Path $ProjetoKpi 'Automacao'
$config = [ordered]@{
    versao = '1.8.9'
    modoManual = [bool]$ManualOnly
    jmsUrl = if ($existingConfig.jmsUrl) { [string]$existingConfig.jmsUrl } else { 'https://jmsbr.jtjms-br.com/index' }
    chrome = $chromeDetectado
    jmsBrowser = $chromeDetectado
    whatsappBrowser = $chromeDetectado
    perfilJms = if ($existingConfig.perfilJms) { [string]$existingConfig.perfilJms } else { (Join-Path $Destino 'chrome-profile') }
    perfilWhatsApp = if ($existingConfig.perfilWhatsApp) { [string]$existingConfig.perfilWhatsApp } else { (Join-Path $Destino 'whatsapp-profile') }
    downloads = if ($existingConfig.downloads) { [string]$existingConfig.downloads } else { '%USERPROFILE%\Downloads' }
    baseDir = if ($existingConfig.baseDir) { [string]$existingConfig.baseDir } else { $baseDir }
    powerBi = if ($existingConfig.powerBi -and (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables([string]$existingConfig.powerBi)))) { [string]$existingConfig.powerBi } else { $powerBi }
    paginaPowerBi = if ($existingConfig.paginaPowerBi) { [string]$existingConfig.paginaPowerBi } else { 'D+0 - RESUMIDO' }
    slaBaseDir = if ($existingConfig.slaBaseDir) { [string]$existingConfig.slaBaseDir } else { (Join-Path $ProjetoKpi 'Base_vencimentos') }
    slaDiasHistorico = 21
    slaBaseEntrega = if ($existingConfig.slaBaseEntrega) { [string]$existingConfig.slaBaseEntrega } elseif ($existingConfig.expedidoBaseSigla) { [string]$existingConfig.expedidoBaseSigla } else { 'THE-PI' }
    slaHorario = if ($existingConfig.slaHorario) { [string]$existingConfig.slaHorario } else { '07:00' }
    slaPaginaPowerBi = if ($existingConfig.slaPaginaPowerBi -and [string]$existingConfig.slaPaginaPowerBi -ne 'SLA - VENCIMENTO') { [string]$existingConfig.slaPaginaPowerBi } else { 'Parcial SLA' }
    slaGrupoFeishu = if ($existingConfig.slaGrupoFeishu) { [string]$existingConfig.slaGrupoFeishu } else { 'MA/PI - Hub/Pdd 网点管理' }
    slaMensagemFeishu = if ($existingConfig.slaMensagemFeishu) { [string]$existingConfig.slaMensagemFeishu } else { "Segue o SLA de {dataFinalJms}.`n`nAtualização gerada pelo Assistente oCoffeIA" }
    logDir = if ($existingConfig.logDir) { [string]$existingConfig.logDir } else { $logDir }
    grupoWhatsApp = $grupoWhatsApp
    nomeGrupoWhatsApp = $nomeGrupo
    intervaloMinutos = 60
    horariosAtualizacao = $horarios
    automacaoPausada = if ($ManualOnly) { $true } elseif ($null -ne $existingConfig.automacaoPausada) { [bool]$existingConfig.automacaoPausada } else { $false }
    mensagem = if ($existingConfig.mensagem) { [string]$existingConfig.mensagem } else { "@all Segue a parcial das {horario}.`n`nAtualização gerada pelo Assistente oCoffeIA" }
    whatsappResponsavel = $whatsappResponsavel
    alertaDesempenhoAtivo = if ($null -ne $existingConfig.alertaDesempenhoAtivo) { [bool]$existingConfig.alertaDesempenhoAtivo } else { [bool]$whatsappResponsavel }
    alertaPercentualMinimo = if ($existingConfig.alertaPercentualMinimo) { [double]$existingConfig.alertaPercentualMinimo } else { 100 }
    alertaMinimoHorasRota = if ($existingConfig.alertaMinimoHorasRota) { [double]$existingConfig.alertaMinimoHorasRota } else { 6 }
    alertaMinimoPedidos = if ($existingConfig.alertaMinimoPedidos) { [int]$existingConfig.alertaMinimoPedidos } else { 10 }
    expedidoBaseSigla = if ($existingConfig.expedidoBaseSigla) { [string]$existingConfig.expedidoBaseSigla } else { 'THE-PI' }
    expedidoBases = if ($existingConfig.expedidoBases) { @($existingConfig.expedidoBases) } elseif ($existingConfig.expedidoBaseSigla) { @([string]$existingConfig.expedidoBaseSigla) } else { @('THE-PI') }
    expedidoModeloPlanilha = if ($existingConfig.expedidoModeloPlanilha) { [string]$existingConfig.expedidoModeloPlanilha } else { (Join-Path $templatesDestino 'Modelo-Expedido-nao-chegou.xlsx') }
    expedidoPastaSaida = if ($existingConfig.expedidoPastaSaida) { [string]$existingConfig.expedidoPastaSaida } else { (Join-Path $env:USERPROFILE 'Downloads\oCoffe-Expedido-nao-chegou') }
}
$modelCandidate = [Environment]::ExpandEnvironmentVariables([string]$config.expedidoModeloPlanilha)
$stableModel = Join-Path $templatesDestino 'Modelo-Expedido-nao-chegou.xlsx'
if (Test-Path -LiteralPath $modelCandidate) {
    $candidatePath = (Resolve-Path -LiteralPath $modelCandidate).Path
    $stablePath = if (Test-Path -LiteralPath $stableModel) { (Resolve-Path -LiteralPath $stableModel).Path } else { $stableModel }
    if ($candidatePath -ne $stablePath) { Copy-Item -LiteralPath $modelCandidate -Destination $stableModel -Force }
    $config.expedidoModeloPlanilha = $stableModel
} elseif (Test-Path -LiteralPath $stableModel) {
    $config.expedidoModeloPlanilha = $stableModel
}
$config | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8
# A interface é executada sem elevação. Como o instalador cria C:\oCoffe como
# administrador, conceda ao mesmo usuário permissão para alterar apenas a
# configuração local (nome do grupo, bases, horários e caminhos).
Grant-LocalUsersConfigAccess -Path $configDir

$baseDirConfigurada = [Environment]::ExpandEnvironmentVariables([string]$config.baseDir)
$slaBaseDirConfigurada = [Environment]::ExpandEnvironmentVariables([string]$config.slaBaseDir)
$logDirConfigurado = [Environment]::ExpandEnvironmentVariables([string]$config.logDir)
New-Item -ItemType Directory -Path $baseDirConfigurada, $slaBaseDirConfigurada, $logDirConfigurado -Force | Out-Null

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $orquestradorDestino)

$triggers = if ($horarios.Count -gt 0) {
    foreach ($horario in $horarios) {
        $hora = [datetime]::ParseExact($horario, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        New-ScheduledTaskTrigger -Daily -At $hora
    }
} else { @() }

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopIfGoingOnBatteries `
    -AllowStartIfOnBatteries

$mainTaskParameters = @{
    TaskName = 'JMS - Atualizar Gestão KPI'
    Action = $action
    Settings = $settings
    Description = 'Atualiza JMS e Power BI somente nos horários configurados e aguarda confirmação antes do WhatsApp.'
    Force = $true
}
if ($triggers.Count -gt 0) { $mainTaskParameters.Trigger = $triggers }
Register-ScheduledTask @mainTaskParameters | Out-Null
if ([bool]$config.automacaoPausada) { Disable-ScheduledTask -TaskName 'JMS - Atualizar Gestão KPI' | Out-Null }

$slaAction=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $orquestradorSlaDestino)
$slaTaskParameters = @{
    TaskName = 'JMS - Atualizar SLA'
    Action = $slaAction
    Settings = $settings
    Description = 'Atualiza o SLA no Power BI, sem captura ou envio.'
    Force = $true
}
if (-not $ManualOnly) {
    $slaTaskParameters.Trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact([string]$config.slaHorario,'HH:mm',[Globalization.CultureInfo]::InvariantCulture))
}
Register-ScheduledTask @slaTaskParameters | Out-Null
if ($ManualOnly) { Disable-ScheduledTask -TaskName 'JMS - Atualizar SLA' | Out-Null }

Write-Host 'oCoffe instalado com sucesso.' -ForegroundColor Green
Write-Host "Script: $processoDestino"
Write-Host "Configuração local: $configFile"
Write-Host "Agendamento: $(if ($horarios.Count) { $horarios -join ', ' } else { 'sem execução automática; configure pela interface' })"
if ($ManualOnly) { Write-Host 'Modo manual: todas as rotinas são iniciadas exclusivamente pelos botões.' -ForegroundColor Green }
Write-Host 'Comando: abra um novo PowerShell e digite ocoffe ajuda'
Write-Host 'Interface: use o atalho oCoffeIA na Área de Trabalho'
Write-Host 'O envio ao WhatsApp somente ocorre após revisar a captura e clicar em Confirmar e enviar.'
Write-Host 'O usuário ainda deve autenticar JMS, Feishu e WhatsApp Web nesta máquina.'





