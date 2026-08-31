$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[Windows.Forms.Application]::EnableVisualStyles()

$script:InstanceCreated = $false
$script:InstanceMutex = [Threading.Mutex]::new($true, 'Local\oCoffeIA.Interface.OC01', [ref]$script:InstanceCreated)
if (-not $script:InstanceCreated) {
    [void][Windows.Forms.MessageBox]::Show(
        'O oCoffeIA já está aberto. O robô OC-01 trabalha em uma única janela por vez.',
        'oCoffeIA — instância única',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Information
    )
    $script:InstanceMutex.Dispose()
    exit
}

$script:Root = 'C:\oCoffe'
$script:ConfigPath = Join-Path $script:Root 'config\gestao-kpi.json'
$script:Version = '1.8.9'
if (Test-Path -LiteralPath $script:ConfigPath) {
    try {
        $versionConfig = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace([string]$versionConfig.versao)) { $script:Version = [string]$versionConfig.versao }
    } catch { }
}
$script:ReportPath = Join-Path $script:Root 'reports'
$script:ReviewScript = Join-Path $script:Root 'processes\whatsapp\Revisar-EnvioWhatsApp.ps1'
$script:ExpedidoScript = Join-Path $script:Root 'processes\expedido\Executar-ExpedidoNaoChegou.ps1'
$script:ExpedidoTimerPath = Join-Path $script:Root 'config\expedido-cronometro.json'
$script:MainTaskName = 'JMS - Atualizar Gestão KPI'
$script:SlaTaskName = 'JMS - Atualizar SLA'
$script:DefaultProject = 'C:\Gestão de KPI_Operacional_v2'
$script:Colors = @{
    Background = [Drawing.Color]::FromArgb(9, 13, 18)
    Surface = [Drawing.Color]::FromArgb(17, 24, 32)
    Surface2 = [Drawing.Color]::FromArgb(24, 34, 44)
    Border = [Drawing.Color]::FromArgb(48, 65, 80)
    Green = [Drawing.Color]::FromArgb(46, 230, 143)
    Cyan = [Drawing.Color]::FromArgb(45, 200, 255)
    Red = [Drawing.Color]::FromArgb(242, 58, 78)
    Gold = [Drawing.Color]::FromArgb(255, 196, 61)
    Text = [Drawing.Color]::FromArgb(235, 242, 247)
    Muted = [Drawing.Color]::FromArgb(145, 165, 181)
}

function Read-OCoffeeConfig {
    if (Test-Path -LiteralPath $script:ConfigPath) {
        try { return Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    return [pscustomobject]@{}
}

function Save-OCoffeeConfig($Config) {
    try {
        $Config | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
    } catch [System.UnauthorizedAccessException] {
        throw "Sem permissão para salvar $script:ConfigPath. Execute novamente o instalador como administrador para reparar as permissões."
    }
}

function Get-ConfigValue($Config, [string]$Name, $Default) {
    if ($Config.PSObject.Properties[$Name] -and -not [string]::IsNullOrWhiteSpace([string]$Config.$Name)) { return $Config.$Name }
    return $Default
}

function Set-ConfigValue($Config, [string]$Name, $Value) {
    if ($Config.PSObject.Properties[$Name]) { $Config.$Name = $Value } else { $Config | Add-Member NoteProperty $Name $Value }
}

function Get-MainTask { Get-ScheduledTask -TaskName $script:MainTaskName -ErrorAction SilentlyContinue }
function Get-SlaTask { Get-ScheduledTask -TaskName $script:SlaTaskName -ErrorAction SilentlyContinue }

function Set-AutomationState([bool]$Enabled) {
    $config = Read-OCoffeeConfig
    if ($Enabled -and [bool](Get-ConfigValue $config 'modoManual' $false)) {
        Show-OCoffeeMessage 'Esta instalação usa o modo manual. Inicie cada rotina pelos botões da interface.' 'Modo manual' ([Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    $tasks = @((Get-MainTask), (Get-SlaTask)) | Where-Object { $_ }
    if ($tasks.Count -eq 0) {
        Show-OCoffeeMessage 'As tarefas automáticas ainda não estão instaladas.' 'Automação' ([Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    foreach ($task in $tasks) {
        if (-not $Enabled -and $task.State -eq 'Running') { Stop-ScheduledTask -TaskName $task.TaskName -ErrorAction SilentlyContinue }
        if ($Enabled) { Enable-ScheduledTask -TaskName $task.TaskName | Out-Null }
        else { Disable-ScheduledTask -TaskName $task.TaskName | Out-Null }
    }
    Set-ConfigValue $config 'automacaoPausada' (-not $Enabled)
    Save-OCoffeeConfig $config
    Write-Terminal $(if($Enabled){'Automação retomada. As rotinas executarão somente nos horários configurados.'}else{'Automação pausada. Nenhuma rotina programada será iniciada.'}) $(if($Enabled){$script:Colors.Green}else{$script:Colors.Gold})
    Refresh-Dashboard
}

function Toggle-AutomationState {
    $task = Get-MainTask
    if (-not $task) { Set-AutomationState $false; return }
    Set-AutomationState ($task.State -eq 'Disabled')
}

function Show-OCoffeeMessage([string]$Text, [string]$Title = 'oCoffeIA', [Windows.Forms.MessageBoxIcon]$Icon = [Windows.Forms.MessageBoxIcon]::Information) {
    [void][Windows.Forms.MessageBox]::Show($Text, $Title, [Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Write-Terminal([string]$Message, [Drawing.Color]$Color = $script:Colors.Cyan) {
    if (-not $script:Terminal) { return }
    $script:Terminal.SelectionStart = $script:Terminal.TextLength
    $script:Terminal.SelectionColor = $script:Colors.Muted
    $script:Terminal.AppendText("[$(Get-Date -Format 'HH:mm:ss')] ")
    $script:Terminal.SelectionColor = $Color
    $script:Terminal.AppendText("$Message`r`n")
    $script:Terminal.ScrollToCaret()
}

function New-Label([Windows.Forms.Control]$Parent, [string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [float]$Size = 10, [Drawing.Color]$Color = $script:Colors.Text, [Drawing.FontStyle]$Style = [Drawing.FontStyle]::Regular) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object Drawing.Point($X, $Y)
    $label.Size = New-Object Drawing.Size($Width, $Height)
    $label.ForeColor = $Color
    $label.Font = New-Object Drawing.Font('Segoe UI', $Size, $Style)
    $Parent.Controls.Add($label)
    return $label
}

function New-Button([Windows.Forms.Control]$Parent, [string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [scriptblock]$Action, [Drawing.Color]$Accent = $script:Colors.Cyan, [string]$Hint = '') {
    $button = New-Object Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object Drawing.Point($X, $Y)
    $button.Size = New-Object Drawing.Size($Width, $Height)
    $button.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = $Accent
    $button.BackColor = $script:Colors.Surface2
    $button.ForeColor = $script:Colors.Text
    $button.Cursor = [Windows.Forms.Cursors]::Hand
    $button.Font = New-Object Drawing.Font('Segoe UI Semibold', 9.5)
    $button.Add_MouseEnter({ $this.BackColor = [Drawing.Color]::FromArgb(34, 48, 61) })
    $button.Add_MouseLeave({ $this.BackColor = $script:Colors.Surface2 })
    $button.Add_Click($Action)
    if ($Hint) { $script:ToolTip.SetToolTip($button, $Hint) }
    $Parent.Controls.Add($button)
    return $button
}

function New-StatusCard([Windows.Forms.Control]$Parent, [string]$Title, [int]$X, [int]$Y, [int]$Width, [string]$Key) {
    $panel = New-Object Windows.Forms.Panel
    $panel.Location = New-Object Drawing.Point($X, $Y)
    $panel.Size = New-Object Drawing.Size($Width, 100)
    $panel.BackColor = $script:Colors.Surface
    $panel.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    $Parent.Controls.Add($panel)
    [void](New-Label $panel $Title 16 12 ($Width - 32) 22 9 $script:Colors.Muted)
    $value = New-Label $panel '--' 16 38 ($Width - 32) 31 16 $script:Colors.Text ([Drawing.FontStyle]::Bold)
    $detail = New-Label $panel 'aguardando leitura' 16 72 ($Width - 32) 20 8.5 $script:Colors.Muted
    $value.Anchor = 'Top,Left,Right'
    $detail.Anchor = 'Top,Left,Right'
    $script:Cards[$Key] = [pscustomobject]@{ Value = $value; Detail = $detail; Panel = $panel }
    return $panel
}

function Set-Card([string]$Key, [string]$Value, [string]$Detail, [Drawing.Color]$Color) {
    $card = $script:Cards[$Key]
    if (-not $card) { return }
    $card.Value.Text = $Value
    $card.Value.ForeColor = $Color
    $card.Detail.Text = $Detail
}

function Get-Paths {
    $config = Read-OCoffeeConfig
    $project = $script:DefaultProject
    return [pscustomobject]@{
        Config = $config
        Base = [Environment]::ExpandEnvironmentVariables([string](Get-ConfigValue $config 'baseDir' (Join-Path $project 'Base_Gestão_de_pedidos_')))
        SlaBase = [Environment]::ExpandEnvironmentVariables([string](Get-ConfigValue $config 'slaBaseDir' (Join-Path $project 'Base_vencimentos')))
        Pbix = [Environment]::ExpandEnvironmentVariables([string](Get-ConfigValue $config 'powerBi' (Join-Path $project 'Gestão de KPI.pbix')))
        LogDir = [Environment]::ExpandEnvironmentVariables([string](Get-ConfigValue $config 'logDir' (Join-Path $project 'Automacao')))
        Jms = [string](Get-ConfigValue $config 'jmsUrl' 'https://jmsbr.jtjms-br.com/index')
        ExpedidoBase = [string](Get-ConfigValue $config 'expedidoBaseSigla' '')
        ExpedidoBases = if ($config.PSObject.Properties['expedidoBases'] -and @($config.expedidoBases).Count) { @($config.expedidoBases) } elseif ($config.expedidoBaseSigla) { @([string]$config.expedidoBaseSigla) } else { @() }
        ExpedidoTemplate = [Environment]::ExpandEnvironmentVariables([string](Get-ConfigValue $config 'expedidoModeloPlanilha' ''))
        ExpedidoOutput = [Environment]::ExpandEnvironmentVariables([string](Get-ConfigValue $config 'expedidoPastaSaida' (Join-Path $env:USERPROFILE 'Downloads\oCoffe-Expedido-nao-chegou')))
    }
}

function Refresh-ConfigurationSummary {
    $paths = Get-Paths
    $times = @($paths.Config.horariosAtualizacao) | Where-Object { $_ }
    $script:ConfigSummary.Text = @"
PERFIL LOCAL     C:\oCoffe
POWER BI         $($paths.Pbix)
BASE ENTREGAS    $($paths.Base)
BASE SLA         $($paths.SlaBase)
ABA PARCIAL      $(Get-ConfigValue $paths.Config 'paginaPowerBi' 'D+0 - RESUMIDO')
ABA SLA          $(Get-ConfigValue $paths.Config 'slaPaginaPowerBi' 'Parcial SLA')
BASE SLA JMS     $(Get-ConfigValue $paths.Config 'slaBaseEntrega' (Get-ConfigValue $paths.Config 'expedidoBaseSigla' 'não configurada'))
HORÁRIOS         $(if($times.Count){$times -join ', '}else{'nenhum horário automático'})
GRUPO WHATSAPP   $(Get-ConfigValue $paths.Config 'nomeGrupoWhatsApp' 'não configurado')
WHATSAPP ALERTA  $(if(Get-ConfigValue $paths.Config 'whatsappResponsavel' ''){'configurado'}else{'não configurado'})
REGRA ALERTA     ao atingir $(Get-ConfigValue $paths.Config 'alertaMinimoHorasRota' 6)h deve estar em $(Get-ConfigValue $paths.Config 'alertaPercentualMinimo' 100)%
GRUPO FEISHU     $(Get-ConfigValue $paths.Config 'slaGrupoFeishu' 'não configurado')
BASES EXPEDIDO    $(if($paths.ExpedidoBases.Count){$paths.ExpedidoBases -join ', '}else{'não configuradas'})
MODELO EXPEDIDO   $(if($paths.ExpedidoTemplate){$paths.ExpedidoTemplate}else{'não configurado'})
SAÍDA EXPEDIDO    $($paths.ExpedidoOutput)
"@
}

function Refresh-TerminalFromLogs {
    $paths = Get-Paths
    $files = @(
        (Join-Path $paths.LogDir 'atualizacao.log'),
        (Join-Path $paths.LogDir 'sla-atualizacao.log'),
        (Join-Path $script:Root 'whatsapp.log')
    )
    $lines = foreach ($file in $files) {
        if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file -Tail 6 -ErrorAction SilentlyContinue }
    }
    $script:Terminal.Clear()
    $script:Terminal.SelectionColor = $script:Colors.Green
    $script:Terminal.AppendText("oCoffeIA Operations Console v$($script:Version)`r`n")
    $script:Terminal.SelectionColor = $script:Colors.Muted
    $script:Terminal.AppendText("------------------------------------------------------------`r`n")
    if ($lines) { $script:Terminal.AppendText(($lines -join "`r`n") + "`r`n") } else { $script:Terminal.AppendText("Nenhuma execução registrada ainda.`r`n") }
    $script:Terminal.ScrollToCaret()
}

function Refresh-Dashboard {
    try {
        $task = Get-MainTask
        if (-not $task) { Set-Card 'auto' 'NÃO INSTALADO' 'execute o instalador do oCoffeIA' $script:Colors.Red }
        else {
            $stateText = if ($task.State -eq 'Disabled') { 'PAUSADO' } elseif ($task.State -eq 'Running') { 'EXECUTANDO' } else { 'ATIVO' }
            $stateColor = if ($task.State -eq 'Disabled') { $script:Colors.Gold } elseif ($task.State -eq 'Running') { $script:Colors.Cyan } else { $script:Colors.Green }
            Set-Card 'auto' $stateText "tarefa: $($task.TaskName)" $stateColor
            $info = Get-ScheduledTaskInfo -TaskName $task.TaskName
            $last = if ($info.LastRunTime.Year -lt 2000) { 'AINDA NÃO' } else { $info.LastRunTime.ToString('dd/MM HH:mm') }
            $lastColor = if ($info.LastTaskResult -eq 0) { $script:Colors.Green } elseif ($info.LastRunTime.Year -lt 2000) { $script:Colors.Muted } else { $script:Colors.Red }
            Set-Card 'last' $last "resultado: $($info.LastTaskResult)" $lastColor
            $next = if ($task.State -eq 'Disabled') { '--' } else { $info.NextRunTime.ToString('dd/MM HH:mm') }
            Set-Card 'next' $next 'próxima parcial programada' $(if($task.State -eq 'Disabled'){$script:Colors.Muted}else{$script:Colors.Cyan})
            if ($script:AutomationToggleButton) {
                $paused = $task.State -eq 'Disabled'
                $script:AutomationToggleButton.Text = if($paused){'[▶] CONTINUAR AUTOMAÇÃO'}else{'[■] PAUSAR AUTOMAÇÃO'}
                $script:AutomationToggleButton.FlatAppearance.BorderColor = if($paused){$script:Colors.Green}else{$script:Colors.Gold}
            }
        }
        $paths = Get-Paths
        $statePath = Join-Path $script:ReportPath 'estado-atualizacao.json'
        $flowText = 'ocioso'
        if (Test-Path -LiteralPath $statePath) {
            try { $flow = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json; $flowText = "$($flow.stage): $($flow.status)" } catch {}
        }
        $latestBase = Get-ChildItem -LiteralPath $paths.Base -Filter '*.xlsx' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $baseText = if($latestBase){"$($latestBase.Name) • $($latestBase.LastWriteTime.ToString('HH:mm'))"}else{'SEM PLANILHA'}
        $script:FooterStatus.Text = "FLUXO: $flowText   |   BASE: $baseText   |   $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
        Refresh-ConfigurationSummary
        Refresh-OperationsCenter $paths
        Refresh-FinalReport
    } catch {
        Set-Card 'auto' 'ERRO' $_.Exception.Message $script:Colors.Red
    }
}

function Refresh-OperationsCenter($Paths) {
    if (-not $script:MissionList) { return }
    $now = Get-Date
    $adminBases = if($Paths.ExpedidoBases.Count){$Paths.ExpedidoBases -join ', '}else{'SEM BASE'}
    $script:DashboardClock.Text = "ADMIN • BASES: $adminBases  •  $($now.ToString('dddd, dd/MM/yyyy  HH:mm:ss'))"

    $script:MissionList.Items.Clear()
    $times = @($Paths.Config.horariosAtualizacao) | Where-Object { $_ } | Sort-Object
    foreach ($time in $times) {
        $planned = [datetime]::Today.Add([timespan]::Parse($time))
        $status = if ($planned -lt $now) { 'CONCLUÍDA/VER LOG' } else { 'AGENDADA' }
        $item = New-Object Windows.Forms.ListViewItem($time)
        [void]$item.SubItems.Add('PARCIAL JMS')
        [void]$item.SubItems.Add($status)
        $item.ForeColor = if ($planned -lt $now) { $script:Colors.Muted } else { $script:Colors.Green }
        [void]$script:MissionList.Items.Add($item)
    }
    $slaTime = [string](Get-ConfigValue $Paths.Config 'slaHorario' '07:00')
    $slaItem = New-Object Windows.Forms.ListViewItem($slaTime)
    [void]$slaItem.SubItems.Add('SLA DIÁRIO')
    [void]$slaItem.SubItems.Add($(if([datetime]::Today.Add([timespan]::Parse($slaTime)) -lt $now){'CONCLUÍDO/VER LOG'}else{'AGENDADO'}))
    $slaItem.ForeColor = $script:Colors.Gold
    [void]$script:MissionList.Items.Add($slaItem)

    $script:RecentActivity.Clear()
    $logFiles = @((Join-Path $Paths.LogDir 'atualizacao.log'), (Join-Path $Paths.LogDir 'sla-atualizacao.log'))
    $recent = foreach ($file in $logFiles) {
        if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file -Tail 6 -ErrorAction SilentlyContinue }
    }
    if ($recent) { $script:RecentActivity.Text = ($recent | Select-Object -Last 10) -join "`r`n" }
    else { $script:RecentActivity.Text = "Aguardando a primeira execução.`r`nAs etapas JMS, planilha, Power BI e revisão aparecerão aqui." }

    $script:HealthList.Items.Clear()
    $health = @(
        @('POWER BI', (Test-Path -LiteralPath $Paths.Pbix)),
        @('BASE ENTREGAS', (Test-Path -LiteralPath $Paths.Base)),
        @('BASE SLA', (Test-Path -LiteralPath $Paths.SlaBase)),
        @('TAREFA PARCIAL', [bool](Get-MainTask)),
        @('TAREFA SLA', [bool](Get-SlaTask))
    )
    foreach ($check in $health) {
        $item = New-Object Windows.Forms.ListViewItem($(if($check[1]){'● ONLINE'}else{'● ATENÇÃO'}))
        [void]$item.SubItems.Add([string]$check[0])
        $item.ForeColor = if ($check[1]) { $script:Colors.Green } else { $script:Colors.Red }
        [void]$script:HealthList.Items.Add($item)
    }
    $ready = @($health | Where-Object { $_[1] }).Count
    $performanceAlertFile = Join-Path $script:ReportPath 'alerta-desempenho.json'
    $performanceAlerts = @()
    $performanceRoutes = @()
    if (Test-Path -LiteralPath $performanceAlertFile) {
        try {
            $performanceResult = Get-Content -LiteralPath $performanceAlertFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([datetime]$performanceResult.generatedAt -ge [datetime]::Today) { $performanceAlerts = @($performanceResult.alertas); $performanceRoutes = @($performanceResult.rotas) }
        } catch {}
    }
    $routesInProgress = @($performanceRoutes | Where-Object { $_.status -eq 'em andamento' })
    $script:OC01Advice.Text = if ($performanceAlerts.Count -gt 0) {
        "OC-01: ATENÇÃO — $($performanceAlerts.Count) rota(s) abaixo do ritmo. Revise o alerta de desempenho."
    } elseif ($routesInProgress.Count -gt 0) {
        $nextDeadline = $routesInProgress | Sort-Object horasRestantes | Select-Object -First 1
        "OC-01: $($routesInProgress.Count) rota(s) em andamento. Próximo prazo: $($nextDeadline.entregador), faltam $($nextDeadline.horasRestantes)h e $($nextDeadline.faltam) pedido(s)."
    } elseif ($ready -eq $health.Count) {
        'OC-01: estação pronta. Vou acompanhar as próximas missões.'
    } else {
        "OC-01: $($health.Count - $ready) item(ns) precisam de atenção. Abra DIAGNÓSTICO."
    }
}

function Start-MainUpdate {
    $task = Get-MainTask
    if (-not $task) { Show-OCoffeeMessage 'A automação ainda não está instalada.' 'oCoffeIA' ([Windows.Forms.MessageBoxIcon]::Warning); return }
    if ($task.State -eq 'Running') { Show-OCoffeeMessage 'A atualização já está em andamento.'; return }
    # A execução manual precisa ocorrer na sessão interativa do usuário para
    # controlar Chrome, Power BI e abrir as telas de revisão. Os horários
    # automáticos continuam usando a tarefa do Agendador do Windows.
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\oCoffe\Executar-oCoffe.ps1"'
    Write-Terminal 'Sequência iniciada: JMS > XLSX > Power BI > revisão.' $script:Colors.Green
    Show-OCoffeeMessage "Atualização iniciada.`r`n`r`nAo final, você verá a tela de revisão antes do WhatsApp."
    Refresh-Dashboard
}

function Open-JmsManual {
    $paths = Get-Paths
    $edgeCandidates = @(
        'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
        'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe')
    )
    $edge = $edgeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $edge) {
        Show-OCoffeeMessage 'Microsoft Edge não foi encontrado. Instale o Edge para usar o acesso manual separado.' 'JMS manual' ([Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    # O perfil manual não compartilha arquivos com o perfil do robô. Isso
    # permite consultar o JMS no Edge enquanto o Chrome segue reservado para
    # os downloads automáticos.
    $manualProfile = 'C:\oCoffe\edge-jms-profile'
    if (-not (Test-Path -LiteralPath $manualProfile)) {
        New-Item -ItemType Directory -Path $manualProfile -Force | Out-Null
    }
    Start-Process -FilePath $edge -ArgumentList @(
        "--user-data-dir=$manualProfile",
        '--new-window',
        $paths.Jms
    )
    Write-Terminal 'JMS manual aberto no Edge com perfil separado da automação.' $script:Colors.Cyan
}

function Start-ManualPowerBIUpdate {
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = 'Escolha a planilha XLSX baixada do JMS'
    $dialog.Filter = 'Planilha do Excel (*.xlsx)|*.xlsx'
    $dialog.InitialDirectory = [Environment]::ExpandEnvironmentVariables([string](Get-Paths).Config.downloads)
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }

    $runner = 'C:\oCoffe\Executar-PowerBI-Manual.ps1'
    if (-not (Test-Path -LiteralPath $runner)) {
        Show-OCoffeeMessage 'O componente do modo manual ainda não está instalado.' 'oCoffeIA' ([Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runner`" -Arquivo `"$($dialog.FileName)`""
    Write-Terminal 'Modo manual iniciado: XLSX escolhido > Power BI > revisão.' $script:Colors.Green
    Show-OCoffeeMessage "Planilha recebida.`r`n`r`nO Power BI será atualizado e a revisão abrirá ao final. O JMS não será acessado."
}

function Refresh-FinalReport {
    if (-not $script:FinalReportList) { return }
    $reportFile = Join-Path $script:ReportPath 'relatorio-final.json'
    if (-not (Test-Path -LiteralPath $reportFile)) {
        $script:FinalReportHeader.Text = 'AGUARDANDO A PRIMEIRA ATUALIZAÇÃO DO POWER BI'
        $script:FinalReportList.Items.Clear()
        return
    }
    try {
        $report = Get-Content -LiteralPath $reportFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $generated = [datetime]$report.generatedAt
        $next = $generated.AddHours(1)
        $script:FinalReportHeader.Text = "ÚLTIMA ATUALIZAÇÃO: $($generated.ToString('dd/MM/yyyy HH:mm'))   •   PRÓXIMA: $($next.ToString('HH:mm'))   •   A ÚLTIMA FICA FIXA ATÉ A PRÓXIMA CONCLUIR"
        $script:FinalReportList.BeginUpdate()
        try {
            $script:FinalReportList.Items.Clear()
            foreach ($route in @($report.rotas | Sort-Object horasDeRota -Descending)) {
                $item = New-Object Windows.Forms.ListViewItem([string]$route.entregador)
                [void]$item.SubItems.Add([string]$route.saida)
                [void]$item.SubItems.Add(("{0:N1} h" -f [double]$route.horasDeRota))
                [void]$item.SubItems.Add("$($route.entregues)/$($route.pedidos)")
                [void]$item.SubItems.Add(("{0:N2}%" -f [double]$route.percentual))
                $statusText = switch ([string]$route.status) { 'concluida' {'CONCLUÍDA'} 'atrasada' {'ATRASADA'} default {'EM ANDAMENTO'} }
                [void]$item.SubItems.Add($statusText)
                $item.ForeColor = switch ([string]$route.status) { 'concluida' {$script:Colors.Green} 'atrasada' {$script:Colors.Red} default {$script:Colors.Gold} }
                [void]$script:FinalReportList.Items.Add($item)
            }
        } finally { $script:FinalReportList.EndUpdate() }
    } catch {
        $script:FinalReportHeader.Text = "ÚLTIMO RELATÓRIO MANTIDO • falha ao recarregar: $($_.Exception.Message)"
    }
}

function Start-SoftwareUpdate {
    $updater = Join-Path $script:Root 'tools\Atualizar-oCoffeIA.ps1'
    if (-not (Test-Path -LiteralPath $updater)) { Show-OCoffeeMessage 'Componente de atualização não encontrado.' 'Atualização' ([Windows.Forms.MessageBoxIcon]::Warning); return }
    $answer = [Windows.Forms.MessageBox]::Show('Verificar e instalar a versão mais recente publicada no GitHub? Configurações e logins serão preservados.', 'Atualizar oCoffeIA', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$updater`"" -Wait
    Show-OCoffeeMessage 'Verificação concluída. Reinicie o oCoffeIA caso uma nova versão tenha sido instalada.' 'Atualização'
}

function Start-SlaUpdate {
    $paths = Get-Paths
    $stateFile = Join-Path $paths.LogDir 'ultimo-sla-processado.json'
    $force = $false
    if (Test-Path -LiteralPath $stateFile) {
        $state = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$state.executionDate -eq (Get-Date -Format 'yyyy-MM-dd')) {
            $answer = [Windows.Forms.MessageBox]::Show("O SLA já foi atualizado hoje.`r`nNormalmente só é necessário uma vez ao dia.`r`n`r`nDeseja executar novamente?", 'SLA diário', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Information)
            if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
            $force = $true
        }
    }
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"C:\oCoffe\Executar-SLA.ps1`""
    if ($force) { $args += ' -Force' }
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $args
    Write-Terminal 'SLA iniciado: JMS > Base_vencimentos > BD_D1 > Power BI.' $script:Colors.Green
}

function Start-ManualSlaUpdate {
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = 'Escolha a planilha Entrega realizada (Lista) do SLA'
    $dialog.Filter = 'Planilha do Excel (*.xlsx)|*.xlsx'
    $dialog.InitialDirectory = [Environment]::ExpandEnvironmentVariables([string](Get-Paths).Config.downloads)
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }

    $defaultDate = (Get-Date).AddDays(-1).ToString('dd/MM/yyyy')
    $dateText = [Microsoft.VisualBasic.Interaction]::InputBox(
        'Informe a data final usada na exportação do SLA (DD/MM/AAAA):',
        'SLA manual | data do relatório',
        $defaultDate
    ).Trim()
    if (-not $dateText) { return }
    $endDate = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($dateText, 'dd/MM/yyyy', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$endDate)) {
        Show-OCoffeeMessage 'Data inválida. Use o formato DD/MM/AAAA.' 'SLA manual' ([Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $runner = 'C:\oCoffe\Executar-SLA-Manual.ps1'
    if (-not (Test-Path -LiteralPath $runner)) {
        Show-OCoffeeMessage 'O componente do SLA manual ainda não está instalado.' 'SLA manual' ([Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    $isoDate = $endDate.ToString('yyyy-MM-dd')
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runner`" -Arquivo `"$($dialog.FileName)`" -DataFinal `"$isoDate`""
    Write-Terminal "SLA manual iniciado: XLSX escolhido > BD_D1 > filtro $dateText > Power BI." $script:Colors.Green
    Show-OCoffeeMessage "Atualização manual do SLA iniciada.`r`n`r`nA tabela BD_D1 será atualizada e o Power BI será salvo ao final."
}

function Review-LatestPartial {
    $latest = Get-ChildItem -LiteralPath $script:ReportPath -Filter 'parcial-*.png' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { Show-OCoffeeMessage 'Ainda não existe uma captura para revisar.'; return }
    $metaPath = [IO.Path]::ChangeExtension($latest.FullName, '.json')
    $reportTime = $latest.LastWriteTime.ToString('o')
    if (Test-Path -LiteralPath $metaPath) {
        try { $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json; if ($meta.reportTime) { $reportTime = [string]$meta.reportTime } } catch {}
    }
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($script:ReviewScript)`" -ImagePath `"$($latest.FullName)`" -ReportTime `"$reportTime`""
}

function Configure-WhatsApp {
    $config = Read-OCoffeeConfig
    $link = [Microsoft.VisualBasic.Interaction]::InputBox('Cole o link de convite do grupo:', 'WhatsApp | passo 1 de 4', [string](Get-ConfigValue $config 'grupoWhatsApp' ''))
    if ([string]::IsNullOrWhiteSpace($link)) { return }
    if ($link -notmatch '^https://chat\.whatsapp\.com/[A-Za-z0-9_-]+/?$') { Show-OCoffeeMessage 'Link inválido. Use https://chat.whatsapp.com/CODIGO' 'Configuração' ([Windows.Forms.MessageBoxIcon]::Warning); return }
    $name = [Microsoft.VisualBasic.Interaction]::InputBox('Digite exatamente o nome visível do grupo:', 'WhatsApp | passo 2 de 4', [string](Get-ConfigValue $config 'nomeGrupoWhatsApp' 'Entregadores J&T - THE'))
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $phone = [Microsoft.VisualBasic.Interaction]::InputBox('WhatsApp do responsável que receberá alertas (DDD + número):', 'WhatsApp | passo 3 de 4', [string](Get-ConfigValue $config 'whatsappResponsavel' ''))
    $phone = $phone -replace '\D', ''
    if ($phone.Length -in 10,11) { $phone = "55$phone" }
    if ($phone -and $phone -notmatch '^\d{12,13}$') { Show-OCoffeeMessage 'Número inválido. Informe DDD + número, por exemplo 86999999999.' 'Configuração' ([Windows.Forms.MessageBoxIcon]::Warning); return }
    $rule = [Microsoft.VisualBasic.Interaction]::InputBox('Regra: prazo máximo em horas e percentual exigido, separados por vírgula. Exemplo: 6,100', 'WhatsApp | passo 4 de 4', "$(Get-ConfigValue $config 'alertaMinimoHorasRota' 6),$(Get-ConfigValue $config 'alertaPercentualMinimo' 100)")
    if ($rule -notmatch '^\s*(\d+(?:[.,]\d+)?)\s*[,;]\s*(\d+(?:[.,]\d+)?)\s*$') { Show-OCoffeeMessage 'Regra inválida. Exemplo: 6,100' 'Configuração' ([Windows.Forms.MessageBoxIcon]::Warning); return }
    $hours = [double]::Parse(($Matches[1] -replace ',','.'), [Globalization.CultureInfo]::InvariantCulture)
    $percent = [double]::Parse(($Matches[2] -replace ',','.'), [Globalization.CultureInfo]::InvariantCulture)
    if ($hours -le 0 -or $percent -le 0 -or $percent -gt 100) { Show-OCoffeeMessage 'Use horas maiores que zero e percentual entre 1 e 100.' 'Configuração' ([Windows.Forms.MessageBoxIcon]::Warning); return }
    Set-ConfigValue $config 'grupoWhatsApp' $link.Trim()
    Set-ConfigValue $config 'nomeGrupoWhatsApp' $name.Trim()
    Set-ConfigValue $config 'whatsappResponsavel' $phone
    Set-ConfigValue $config 'alertaDesempenhoAtivo' ([bool]$phone)
    Set-ConfigValue $config 'alertaMinimoHorasRota' $hours
    Set-ConfigValue $config 'alertaPercentualMinimo' $percent
    Set-ConfigValue $config 'alertaMinimoPedidos' 10
    Save-OCoffeeConfig $config
    Refresh-ConfigurationSummary
    Show-OCoffeeMessage 'WhatsApp e regra de desempenho salvos. Todo alerta exigirá confirmação antes do envio.'
}

function Configure-Schedules {
    $config = Read-OCoffeeConfig
    $current = @($config.horariosAtualizacao) | Where-Object { $_ }
    $default = if ($current.Count) { $current -join ', ' } else { '08:00, 10:00, 12:00, 14:00, 16:00' }
    $input = [Microsoft.VisualBasic.Interaction]::InputBox('Horários separados por vírgula. Exemplo: 08:00, 10:30, 13:00', 'Programar parciais', $default)
    if ([string]::IsNullOrWhiteSpace($input)) { return }
    $times = New-Object Collections.Generic.List[string]
    foreach ($item in ($input -split '[,;\s]+' | Where-Object { $_ })) {
        if ($item -notmatch '^(?:[01]?\d|2[0-3]):[0-5]\d$') { Show-OCoffeeMessage "Horário inválido: $item" 'Configuração' ([Windows.Forms.MessageBoxIcon]::Warning); return }
        $normalized = ([datetime]::ParseExact($item.PadLeft(5, '0'), 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)).ToString('HH:mm')
        if (-not $times.Contains($normalized)) { $times.Add($normalized) }
    }
    $ordered = @($times | Sort-Object)
    $task = Get-MainTask
    if (-not $task) { Show-OCoffeeMessage 'A tarefa automática ainda não está instalada.' 'Configuração' ([Windows.Forms.MessageBoxIcon]::Warning); return }
    $triggers = foreach ($timeText in $ordered) { New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact($timeText, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)) }
    Set-ScheduledTask -TaskName $task.TaskName -Trigger $triggers | Out-Null
    $hiddenAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\oCoffe\Executar-oCoffe.ps1"'
    Set-ScheduledTask -TaskName $task.TaskName -Action $hiddenAction | Out-Null
    Set-ConfigValue $config 'horariosAtualizacao' $ordered
    Save-OCoffeeConfig $config
    Refresh-Dashboard
    Show-OCoffeeMessage "Horários salvos:`r`n$($ordered -join ', ')"
}

function Configure-Files {
    $paths = Get-Paths
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = '1 de 2 | Selecione Gestão de KPI.pbix'
    $dialog.Filter = 'Power BI (*.pbix)|*.pbix'
    if (Test-Path -LiteralPath $paths.Pbix) { $dialog.FileName = $paths.Pbix }
    if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
    $folder = New-Object Windows.Forms.FolderBrowserDialog
    $folder.Description = '2 de 2 | Selecione a pasta Base_Gestão_de_pedidos_'
    if (Test-Path -LiteralPath $paths.Base) { $folder.SelectedPath = $paths.Base }
    if ($folder.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
    $config = $paths.Config
    $page = [Microsoft.VisualBasic.Interaction]::InputBox('Nome exato da aba da parcial:', 'Aba Power BI', [string](Get-ConfigValue $config 'paginaPowerBi' 'D+0 - RESUMIDO'))
    Set-ConfigValue $config 'powerBi' $dialog.FileName
    Set-ConfigValue $config 'baseDir' $folder.SelectedPath
    Set-ConfigValue $config 'logDir' (Join-Path (Split-Path -Parent $dialog.FileName) 'Automacao')
    if (-not [string]::IsNullOrWhiteSpace($page)) { Set-ConfigValue $config 'paginaPowerBi' $page.Trim() }
    Save-OCoffeeConfig $config
    Refresh-Dashboard
    Show-OCoffeeMessage 'PBIX, base e aba foram salvos.'
}

function Configure-Sla {
    $config = Read-OCoffeeConfig
    $time = [Microsoft.VisualBasic.Interaction]::InputBox('Horário diário do SLA (HH:mm):', 'SLA | passo 1 de 3', [string](Get-ConfigValue $config 'slaHorario' '07:00'))
    if ($time -notmatch '^(?:[01]\d|2[0-3]):[0-5]\d$') { Show-OCoffeeMessage 'Horário inválido. Use HH:mm.' 'SLA' ([Windows.Forms.MessageBoxIcon]::Warning); return }
    $base = [Microsoft.VisualBasic.Interaction]::InputBox('Sigla exata da Base de entrega no JMS. Exemplo: THE-PI:', 'SLA | passo 2 de 3', [string](Get-ConfigValue $config 'slaBaseEntrega' (Get-ConfigValue $config 'expedidoBaseSigla' 'THE-PI'))).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($base)) { return }
    $group = [Microsoft.VisualBasic.Interaction]::InputBox('Nome exato do grupo no Feishu:', 'SLA | passo 3 de 3', [string](Get-ConfigValue $config 'slaGrupoFeishu' 'MA/PI - Hub/Pdd 网点管理'))
    if ([string]::IsNullOrWhiteSpace($group)) { return }
    Set-ConfigValue $config 'slaHorario' $time
    Set-ConfigValue $config 'slaDiasHistorico' 21
    Set-ConfigValue $config 'slaBaseEntrega' $base
    Set-ConfigValue $config 'slaGrupoFeishu' $group.Trim()
    Save-OCoffeeConfig $config
    $task = Get-SlaTask
    if ($task) {
        $trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact($time, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture))
        Set-ScheduledTask -TaskName $task.TaskName -Trigger $trigger | Out-Null
    }
    Refresh-Dashboard
    Show-OCoffeeMessage "SLA programado diariamente às $time."
}

function Configure-Expedido {
    $config = Read-OCoffeeConfig
    $currentBases = if ($config.PSObject.Properties['expedidoBases']) { @($config.expedidoBases) } else { @([string](Get-ConfigValue $config 'expedidoBaseSigla' 'THE-PI')) }
    $baseText = [Microsoft.VisualBasic.Interaction]::InputBox('Informe todas as siglas administradas, separadas por vírgula. Exemplo: THE-PI, RSO-MA, SLZ-MA:', 'Expedido | passo 1 de 3', ($currentBases -join ', '))
    if ([string]::IsNullOrWhiteSpace($baseText)) { return }
    $bases = @($baseText -split '[,;]' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    if (-not $bases.Count) { Show-OCoffeeMessage 'Informe pelo menos uma base.' 'Expedido' ([Windows.Forms.MessageBoxIcon]::Warning); return }
    $currentModel = [Environment]::ExpandEnvironmentVariables([string](Get-ConfigValue $config 'expedidoModeloPlanilha' ''))
    $selectedModel = $currentModel
    $keepModel = (Test-Path -LiteralPath $currentModel)
    if ($keepModel) {
        $change = [Windows.Forms.MessageBox]::Show("Modelo atual encontrado:`r`n$currentModel`r`n`r`nDeseja trocar o modelo?", 'Expedido | passo 2 de 3', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
        $keepModel = $change -eq [Windows.Forms.DialogResult]::No
    }
    if (-not $keepModel) {
        $model = New-Object Windows.Forms.OpenFileDialog
        $model.Title = 'Expedido | passo 2 de 3 — selecione o modelo Excel'
        $model.Filter = 'Planilha Excel (*.xlsx)|*.xlsx'
        $model.CheckFileExists = $true
        $model.CheckPathExists = $true
        $model.DefaultExt = 'xlsx'
        $model.AddExtension = $true
        if ($currentModel) {
            $directory = Split-Path -Parent $currentModel
            if (Test-Path -LiteralPath $directory) { $model.InitialDirectory = $directory }
        }
        if ($model.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
        $selectedModel = $model.FileName
    }

    $currentOutput = [Environment]::ExpandEnvironmentVariables([string](Get-ConfigValue $config 'expedidoPastaSaida' (Join-Path $env:USERPROFILE 'Downloads\oCoffe-Expedido-nao-chegou')))
    $selectedOutput = $currentOutput
    if (-not (Test-Path -LiteralPath $currentOutput)) { New-Item -ItemType Directory -Path $currentOutput -Force | Out-Null }
    $changeOutput = [Windows.Forms.MessageBox]::Show("Pasta de saída atual:`r`n$currentOutput`r`n`r`nDeseja trocar a pasta?", 'Expedido | passo 3 de 3', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
    if ($changeOutput -eq [Windows.Forms.DialogResult]::Yes) {
        $output = New-Object Windows.Forms.FolderBrowserDialog
        $output.Description = 'Escolha onde salvar as planilhas prontas'
        $output.SelectedPath = $currentOutput
        if ($output.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
        $selectedOutput = $output.SelectedPath
    }
    Set-ConfigValue $config 'expedidoBases' $bases
    Set-ConfigValue $config 'expedidoBaseSigla' $bases[0]
    Set-ConfigValue $config 'expedidoModeloPlanilha' $selectedModel
    Set-ConfigValue $config 'expedidoPastaSaida' $selectedOutput
    Save-OCoffeeConfig $config
    Refresh-Dashboard
    Show-OCoffeeMessage 'Base, modelo e pasta do processo foram salvos. Esse processo nunca entra no agendamento automático.' 'Expedido, mas não chegou'
}

function Save-ExpedidoTimerState($State) {
    $State | ConvertTo-Json | Set-Content -LiteralPath $script:ExpedidoTimerPath -Encoding UTF8
}

function Read-ExpedidoTimerState {
    if (Test-Path -LiteralPath $script:ExpedidoTimerPath) {
        try { return Get-Content -LiteralPath $script:ExpedidoTimerPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    return [pscustomobject]@{ active=$false; status='não iniciado'; warnedTwoHours=$false }
}

function Refresh-ExpedidoTimer {
    if (-not $script:ExpedidoTimerLabel) { return }
    $state = Read-ExpedidoTimerState
    if (-not [bool]$state.active) {
        $script:ExpedidoTimerLabel.Text = "CRONÔMETRO: $([string](Get-ConfigValue $state 'status' 'não iniciado'))"
        $script:ExpedidoTimerLabel.ForeColor = $script:Colors.Muted
        return
    }
    $deadline = [datetime]$state.deadline
    $remaining = $deadline - (Get-Date)
    if ($remaining.TotalSeconds -le 0) {
        $script:ExpedidoTimerLabel.Text = "PRAZO ESGOTADO — limite era $($deadline.ToString('dd/MM HH:mm'))"
        $script:ExpedidoTimerLabel.ForeColor = $script:Colors.Red
        if (-not [bool]$state.expiredWarningShown) {
            Set-ConfigValue $state 'expiredWarningShown' $true
            Save-ExpedidoTimerState $state
            Show-OCoffeeMessage 'O prazo de 6 horas do veículo terminou. Revise o lançamento imediatamente: atraso pode gerar risco de extravio para a base.' 'Prazo esgotado' ([Windows.Forms.MessageBoxIcon]::Error)
        }
        return
    }
    $script:ExpedidoTimerLabel.Text = 'TEMPO RESTANTE: {0:00}:{1:00}:{2:00}  |  limite {3}' -f [math]::Floor($remaining.TotalHours), $remaining.Minutes, $remaining.Seconds, $deadline.ToString('dd/MM HH:mm')
    $script:ExpedidoTimerLabel.ForeColor = if($remaining.TotalHours -le 2){$script:Colors.Gold}else{$script:Colors.Green}
    if ($remaining.TotalHours -le 2 -and -not [bool]$state.warnedTwoHours) {
        Set-ConfigValue $state 'warnedTwoHours' $true
        Save-ExpedidoTimerState $state
        Show-OCoffeeMessage 'Faltam 2 horas para terminar o prazo do veículo.' 'Atenção ao prazo' ([Windows.Forms.MessageBoxIcon]::Warning)
    }
}

function Stop-ExpedidoTimer {
    $state = Read-ExpedidoTimerState
    if (-not [bool]$state.active) { Show-OCoffeeMessage 'O cronômetro não está ativo.'; return }
    $answer = [Windows.Forms.MessageBox]::Show('Deseja parar somente o cronômetro deste veículo? Os arquivos já produzidos não serão apagados.', 'Parar cronômetro', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    Set-ConfigValue $state 'active' $false
    Set-ConfigValue $state 'status' "parado pelo líder às $(Get-Date -Format 'HH:mm')"
    Save-ExpedidoTimerState $state
    Refresh-ExpedidoTimer
}

function Start-ExpedidoProcess {
    $paths = Get-Paths
    if (-not $paths.ExpedidoBases.Count -or -not (Test-Path -LiteralPath $paths.ExpedidoTemplate)) {
        Show-OCoffeeMessage 'Configure primeiro a base e o modelo no botão EXPEDIDO / BASE E MODELO.' 'Configuração necessária' ([Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    $base = if ($paths.ExpedidoBases.Count -eq 1) { [string]$paths.ExpedidoBases[0] } else {
        [Microsoft.VisualBasic.Interaction]::InputBox("Qual base será analisada?`r`n`r`nCadastradas: $($paths.ExpedidoBases -join ', ')", 'Selecionar base', [string]$paths.ExpedidoBases[0]).Trim().ToUpperInvariant()
    }
    if (-not $base) { return }
    if ($paths.ExpedidoBases -notcontains $base) { Show-OCoffeeMessage 'A base informada não está na lista administrada. Cadastre-a primeiro em CONFIGURAÇÃO.' 'Base não cadastrada' ([Windows.Forms.MessageBoxIcon]::Warning); return }
    $defaultTime = (Get-Date).ToString('HH:mm')
    $text = [Microsoft.VisualBasic.Interaction]::InputBox('Qual horário o veículo foi deslacrado? Use HH:mm.', 'Iniciar Expedido, mas não chegou', $defaultTime)
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $time = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($text.Trim(), 'HH:mm', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$time)) {
        Show-OCoffeeMessage 'Horário inválido. Use HH:mm, por exemplo 09:57.' 'Horário do deslacramento' ([Windows.Forms.MessageBoxIcon]::Warning); return
    }
    $unsealed = [datetime]::Today.Add($time.TimeOfDay)
    if ($unsealed -gt (Get-Date).AddMinutes(1)) { $unsealed = $unsealed.AddDays(-1) }
    $deadline = $unsealed.AddHours(6)
    $answer = [Windows.Forms.MessageBox]::Show("Deslacramento: $($unsealed.ToString('dd/MM/yyyy HH:mm'))`r`nPrazo de 6 horas: $($deadline.ToString('dd/MM/yyyy HH:mm'))`r`n`r`nIniciar agora a consulta automática?", 'Confirmar processo manual', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    $state = [pscustomobject]@{ active=$true; status='em andamento'; unsealedAt=$unsealed.ToString('o'); deadline=$deadline.ToString('o'); warnedTwoHours=$false; expiredWarningShown=$false }
    Save-ExpedidoTimerState $state
    Refresh-ExpedidoTimer
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($script:ExpedidoScript)`" -UnsealedAt `"$($unsealed.ToString('o'))`" -BaseSigla `"$base`""
    Write-Terminal "Expedido, mas não chegou iniciado para $base. Prazo: $($deadline.ToString('HH:mm'))." $script:Colors.Green
}

function Run-Diagnostics {
    $script:Diagnostics.Items.Clear()
    $paths = Get-Paths
    $checks = @(
        @('Configuração local', (Test-Path -LiteralPath $script:ConfigPath), $script:ConfigPath),
        @('Node.js', [bool](Get-Command node.exe -ErrorAction SilentlyContinue), 'necessário para o navegador'),
        @('Google Chrome', (Test-Path -LiteralPath ([string](Get-ConfigValue $paths.Config 'chrome' ''))), [string](Get-ConfigValue $paths.Config 'chrome' 'não configurado')),
        @('Arquivo Power BI', (Test-Path -LiteralPath $paths.Pbix), $paths.Pbix),
        @('Base de entregas', (Test-Path -LiteralPath $paths.Base), $paths.Base),
        @('Base do SLA', (Test-Path -LiteralPath $paths.SlaBase), $paths.SlaBase),
        @('Modelo Expedido', (Test-Path -LiteralPath $paths.ExpedidoTemplate), $paths.ExpedidoTemplate),
        @('Automação horária', [bool](Get-MainTask), $script:MainTaskName),
        @('Automação SLA', [bool](Get-SlaTask), $script:SlaTaskName),
        @('Feishu Desktop', ((Test-Path (Join-Path $env:LOCALAPPDATA 'Feishu\app\Feishu.exe')) -or [bool](Get-Process Feishu -ErrorAction SilentlyContinue)), 'necessário apenas para o SLA')
    )
    $okCount = 0
    foreach ($check in $checks) {
        $ok = [bool]$check[1]
        if ($ok) { $okCount++ }
        $item = New-Object Windows.Forms.ListViewItem($(if($ok){'ONLINE'}else{'ATENÇÃO'}))
        [void]$item.SubItems.Add([string]$check[0])
        [void]$item.SubItems.Add([string]$check[2])
        $item.ForeColor = if ($ok) { $script:Colors.Green } else { $script:Colors.Gold }
        [void]$script:Diagnostics.Items.Add($item)
    }
    Write-Terminal "Diagnóstico concluído: $okCount/$($checks.Count) itens prontos." $(if($okCount -eq $checks.Count){$script:Colors.Green}else{$script:Colors.Gold})
}

$form = New-Object Windows.Forms.Form
$form.Text = 'oCoffeIA // Operations Console'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object Drawing.Size(1280, 900)
$form.MinimumSize = New-Object Drawing.Size(1100, 800)
$form.BackColor = $script:Colors.Background
$form.ForeColor = $script:Colors.Text
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.KeyPreview = $true
$script:ToolTip = New-Object Windows.Forms.ToolTip
$script:ToolTip.AutoPopDelay = 8000

$header = New-Object Windows.Forms.Panel
$header.Dock = [Windows.Forms.DockStyle]::Top
$header.Height = 82
$header.BackColor = $script:Colors.Surface
$form.Controls.Add($header)
[void](New-Label $header '>_ oCoffeIA' 24 13 260 37 23 $script:Colors.Green ([Drawing.FontStyle]::Bold))
[void](New-Label $header 'OPERATIONS CONSOLE // Gestão de KPI' 28 51 390 20 9 $script:Colors.Muted)
$versionLabel = New-Label $header "LOCAL MODE  |  v$($script:Version)  |  SEM IA" 780 27 285 28 10 $script:Colors.Cyan ([Drawing.FontStyle]::Bold)
$versionLabel.TextAlign = [Drawing.ContentAlignment]::MiddleRight
$tabs = New-Object Windows.Forms.TabControl
$tabs.Location = New-Object Drawing.Point(18, 94)
$tabs.Size = New-Object Drawing.Size(1066, 730)
$tabs.Anchor = 'Top,Bottom,Left,Right'
$tabs.DrawMode = [Windows.Forms.TabDrawMode]::OwnerDrawFixed
$tabs.ItemSize = New-Object Drawing.Size(170, 36)
$tabs.SizeMode = [Windows.Forms.TabSizeMode]::Fixed
$tabs.Add_DrawItem({
    param($sender, $eventArgs)
    $selected = ($eventArgs.Index -eq $sender.SelectedIndex)
    $background = if ($selected) { $script:Colors.Surface2 } else { $script:Colors.Background }
    $foreground = if ($selected) { $script:Colors.Green } else { $script:Colors.Muted }
    $brush = New-Object Drawing.SolidBrush($background)
    try {
        $eventArgs.Graphics.FillRectangle($brush, $eventArgs.Bounds)
        $flags = [Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::SingleLine
        [Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics, $sender.TabPages[$eventArgs.Index].Text, $sender.Font, $eventArgs.Bounds, $foreground, $background, $flags)
    } finally { $brush.Dispose() }
})
$form.Controls.Add($tabs)

function New-Tab([string]$Text) {
    $page = New-Object Windows.Forms.TabPage
    $page.Text = $Text
    $page.BackColor = $script:Colors.Background
    $page.ForeColor = $script:Colors.Text
    $page.Padding = New-Object Windows.Forms.Padding(16)
    [void]$tabs.TabPages.Add($page)
    return $page
}

$dashboard = New-Tab '01  PAINEL'
$automation = New-Tab '02  AUTOMAÇÃO'
$configuration = New-Tab '03  CONFIGURAÇÃO'
$diagnostic = New-Tab '04  DIAGNÓSTICO'
$finalReport = New-Tab '05  RELATÓRIO FINAL'
$script:Cards = @{}

$dashboardClockPanel = New-Object Windows.Forms.Panel
$dashboardClockPanel.Location = New-Object Drawing.Point(18, 10)
$dashboardClockPanel.Size = New-Object Drawing.Size(1009, 36)
$dashboardClockPanel.Anchor = 'Top,Left,Right'
$dashboardClockPanel.BackColor = $script:Colors.Surface2
$dashboard.Controls.Add($dashboardClockPanel)
$script:DashboardClock = New-Label $dashboardClockPanel 'ESTAÇÃO THE-PI' 14 6 970 24 9.5 $script:Colors.Cyan ([Drawing.FontStyle]::Bold)
$script:DashboardClock.Anchor = 'Top,Left,Right'

$statusGrid = New-Object Windows.Forms.TableLayoutPanel
$statusGrid.Location = New-Object Drawing.Point(18, 58)
$statusGrid.Size = New-Object Drawing.Size(1009, 100)
$statusGrid.Anchor = 'Top,Left,Right'
$statusGrid.ColumnCount = 3; $statusGrid.RowCount = 1
foreach($percent in @(33.33,33.34,33.33)){[void]$statusGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,$percent)))}
$dashboard.Controls.Add($statusGrid)
foreach($cardInfo in @(@('AUTOMAÇÃO','auto'),@('ÚLTIMA EXECUÇÃO','last'),@('PRÓXIMA EXECUÇÃO','next'))){
    $column = $statusGrid.Controls.Count
    $card = New-StatusCard $statusGrid $cardInfo[0] 0 0 315 $cardInfo[1]
    $card.Dock = 'Fill'; $card.Margin = New-Object Windows.Forms.Padding(0,0,$(if($column -lt 2){14}else{0}),0)
    $statusGrid.SetColumn($card,$column)
}
[void](New-Label $dashboard 'EXECUÇÃO RÁPIDA' 18 174 300 25 10 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
$actionGrid = New-Object Windows.Forms.TableLayoutPanel
$actionGrid.Location = New-Object Drawing.Point(18, 204)
$actionGrid.Size = New-Object Drawing.Size(1009, 58)
$actionGrid.Anchor = 'Top,Left,Right'
$actionGrid.ColumnCount = 3; $actionGrid.RowCount = 1
foreach($percent in @(33.33,33.34,33.33)){[void]$actionGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,$percent)))}
$dashboard.Controls.Add($actionGrid)
$quickButtons = @(
    (New-Button $actionGrid '[▶] ATUALIZAR PARCIAL AGORA' 0 0 315 58 { Start-MainUpdate } $script:Colors.Green 'Baixa o JMS, atualiza o Power BI e abre a revisão do WhatsApp.'),
    (New-Button $actionGrid '[◆] ATUALIZAR SLA DIÁRIO' 0 0 315 58 { Start-SlaUpdate } $script:Colors.Gold 'Atualiza o SLA no Power BI sem captura ou envio.'),
    (New-Button $actionGrid '[✓] REVISAR ÚLTIMA PARCIAL' 0 0 315 58 { Review-LatestPartial } $script:Colors.Cyan 'Abre novamente a última imagem sem enviar automaticamente.')
)
for($i=0;$i -lt $quickButtons.Count;$i++){$quickButtons[$i].Dock='Fill';$quickButtons[$i].Margin=New-Object Windows.Forms.Padding(0,0,$(if($i -lt 2){14}else{0}),0);$actionGrid.SetColumn($quickButtons[$i],$i)}
[void](New-Label $dashboard 'FLUXO DA MISSÃO' 18 272 300 25 10 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
$flowPanel = New-Object Windows.Forms.Panel
$flowPanel.Location = New-Object Drawing.Point(18, 306)
$flowPanel.Size = New-Object Drawing.Size(1009, 130)
$flowPanel.Anchor = 'Top,Left,Right'
$flowPanel.BackColor = $script:Colors.Surface
$flowPanel.BorderStyle = 'FixedSingle'
$dashboard.Controls.Add($flowPanel)
$flowGrid = New-Object Windows.Forms.TableLayoutPanel
$flowGrid.Dock = 'Fill'; $flowGrid.ColumnCount = 4; $flowGrid.RowCount = 1
foreach($percent in @(25,25,25,25)){[void]$flowGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,$percent)))}
$flowPanel.Controls.Add($flowGrid)
$steps = @(@('01','JMS','consulta e exportação'),@('02','PLANILHA','substituição segura'),@('03','POWER BI','dados e filtros'),@('04','REVISÃO','você confirma o envio'))
for($i=0;$i -lt $steps.Count;$i++){
    $stepPanel = New-Object Windows.Forms.Panel; $stepPanel.Dock='Fill';$stepPanel.Margin=New-Object Windows.Forms.Padding(8)
    [void](New-Label $stepPanel $steps[$i][0] 8 22 42 32 17 $script:Colors.Green ([Drawing.FontStyle]::Bold))
    $stepTitle=New-Label $stepPanel $steps[$i][1] 55 20 175 25 11 $script:Colors.Text ([Drawing.FontStyle]::Bold);$stepTitle.Anchor='Top,Left,Right'
    $stepDetail=New-Label $stepPanel $steps[$i][2] 55 50 175 22 8.5 $script:Colors.Muted;$stepDetail.Anchor='Top,Left,Right'
    if($i -lt 3){$arrow=New-Label $stepPanel '>>' 222 31 35 25 12 $script:Colors.Cyan ([Drawing.FontStyle]::Bold);$arrow.Anchor='Top,Right'}
    $flowGrid.Controls.Add($stepPanel,$i,0)
}
$onboardingBar = New-Object Windows.Forms.Panel
$onboardingBar.Location=New-Object Drawing.Point(18,450);$onboardingBar.Size=New-Object Drawing.Size(1009,48);$onboardingBar.Anchor='Top,Left,Right';$onboardingBar.BackColor=$script:Colors.Surface2
$dashboard.Controls.Add($onboardingBar)
$firstUse = New-Label $onboardingBar 'PRIMEIRO USO? Configure arquivos → grupo → horários. Depois clique em Atualizar parcial agora.' 14 11 760 28 10 $script:Colors.Gold
$firstUse.Anchor = 'Top,Left,Right'
$guideButton = New-Button $onboardingBar 'ABRIR GUIA RÁPIDO' 805 5 190 38 {
    Show-OCoffeeMessage "GUIA RÁPIDO`r`n`r`n1. Vá em CONFIGURAÇÃO e escolha o PBIX e as pastas.`r`n2. Configure o grupo do WhatsApp e os horários.`r`n3. Faça login no JMS e WhatsApp quando solicitado.`r`n4. Use ATUALIZAR PARCIAL AGORA.`r`n5. Confira a imagem antes de enviar.`r`n`r`nO oCoffeIA funciona localmente e não usa IA online."
} $script:Colors.Gold
$guideButton.Anchor = 'Top,Right'

$operationsGrid = New-Object Windows.Forms.TableLayoutPanel
$operationsGrid.Location = New-Object Drawing.Point(18, 510)
$operationsGrid.Size = New-Object Drawing.Size(1009, 190)
$operationsGrid.Anchor = 'Top,Bottom,Left,Right'
$operationsGrid.ColumnCount = 3; $operationsGrid.RowCount = 1
foreach($percent in @(38,32,30)){[void]$operationsGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,$percent)))}
$dashboard.Controls.Add($operationsGrid)

$activityPanel = New-Object Windows.Forms.Panel; $activityPanel.Size=New-Object Drawing.Size(360,220);$activityPanel.Dock='Fill';$activityPanel.Margin=New-Object Windows.Forms.Padding(0,0,12,0);$activityPanel.BackColor=$script:Colors.Surface;$activityPanel.BorderStyle='FixedSingle'
[void](New-Label $activityPanel 'ATIVIDADE RECENTE' 14 10 300 24 10 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
$script:RecentActivity = New-Object Windows.Forms.RichTextBox;$script:RecentActivity.Location=New-Object Drawing.Point(14,42);$script:RecentActivity.Size=New-Object Drawing.Size(340,150);$script:RecentActivity.Anchor='Top,Bottom,Left,Right';$script:RecentActivity.ReadOnly=$true;$script:RecentActivity.BorderStyle='None';$script:RecentActivity.BackColor=$script:Colors.Surface;$script:RecentActivity.ForeColor=$script:Colors.Muted;$script:RecentActivity.Font=New-Object Drawing.Font('Consolas',8.5);$activityPanel.Controls.Add($script:RecentActivity)
$operationsGrid.Controls.Add($activityPanel,0,0)

$missionPanel = New-Object Windows.Forms.Panel;$missionPanel.Size=New-Object Drawing.Size(310,220);$missionPanel.Dock='Fill';$missionPanel.Margin=New-Object Windows.Forms.Padding(0,0,12,0);$missionPanel.BackColor=$script:Colors.Surface;$missionPanel.BorderStyle='FixedSingle'
[void](New-Label $missionPanel 'AGENDA DE MISSÕES' 14 10 300 24 10 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
$script:MissionList=New-Object Windows.Forms.ListView;$script:MissionList.Location=New-Object Drawing.Point(14,42);$script:MissionList.Size=New-Object Drawing.Size(285,150);$script:MissionList.Anchor='Top,Bottom,Left,Right';$script:MissionList.View='Details';$script:MissionList.FullRowSelect=$true;$script:MissionList.BorderStyle='None';$script:MissionList.BackColor=$script:Colors.Surface;$script:MissionList.ForeColor=$script:Colors.Text;[void]$script:MissionList.Columns.Add('HORA',62);[void]$script:MissionList.Columns.Add('ROTINA',105);[void]$script:MissionList.Columns.Add('ESTADO',120);$missionPanel.Controls.Add($script:MissionList)
$operationsGrid.Controls.Add($missionPanel,1,0)

$healthPanel = New-Object Windows.Forms.Panel;$healthPanel.Size=New-Object Drawing.Size(290,220);$healthPanel.Dock='Fill';$healthPanel.Margin=New-Object Windows.Forms.Padding(0);$healthPanel.BackColor=$script:Colors.Surface;$healthPanel.BorderStyle='FixedSingle'
[void](New-Label $healthPanel 'SAÚDE DA ESTAÇÃO' 14 10 300 24 10 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
$script:HealthList=New-Object Windows.Forms.ListView;$script:HealthList.Location=New-Object Drawing.Point(14,42);$script:HealthList.Size=New-Object Drawing.Size(270,112);$script:HealthList.Anchor='Top,Left,Right';$script:HealthList.View='Details';$script:HealthList.HeaderStyle='None';$script:HealthList.BorderStyle='None';$script:HealthList.BackColor=$script:Colors.Surface;$script:HealthList.ForeColor=$script:Colors.Text;[void]$script:HealthList.Columns.Add('STATUS',100);[void]$script:HealthList.Columns.Add('ITEM',160);$healthPanel.Controls.Add($script:HealthList)
$script:OC01Advice=New-Label $healthPanel 'OC-01 inicializando telemetria...' 14 164 270 45 8.5 $script:Colors.Gold ([Drawing.FontStyle]::Bold);$script:OC01Advice.Dock='Bottom'
$operationsGrid.Controls.Add($healthPanel,2,0)

[void](New-Label $finalReport 'HORAS DESDE A SAÍDA PARA ENTREGA' 18 18 600 30 14 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
$script:FinalReportHeader = New-Label $finalReport 'Carregando último relatório...' 18 54 994 28 9.5 $script:Colors.Gold ([Drawing.FontStyle]::Bold)
$script:FinalReportList = New-Object Windows.Forms.ListView
$script:FinalReportList.Location = New-Object Drawing.Point(18, 94)
$script:FinalReportList.Size = New-Object Drawing.Size(994, 530)
$script:FinalReportList.Anchor = 'Top,Bottom,Left,Right'
$script:FinalReportList.View = 'Details'
$script:FinalReportList.FullRowSelect = $true
$script:FinalReportList.GridLines = $true
$script:FinalReportList.BackColor = $script:Colors.Surface
$script:FinalReportList.ForeColor = $script:Colors.Text
$script:FinalReportList.BorderStyle = 'FixedSingle'
[void]$script:FinalReportList.Columns.Add('RESPONSÁVEL',340)
[void]$script:FinalReportList.Columns.Add('SAÍDA',145)
[void]$script:FinalReportList.Columns.Add('EM ROTA',100)
[void]$script:FinalReportList.Columns.Add('ENTREGAS',105)
[void]$script:FinalReportList.Columns.Add('PERCENTUAL',110)
[void]$script:FinalReportList.Columns.Add('STATUS',155)
$finalReport.Controls.Add($script:FinalReportList)
[void](New-Button $finalReport 'ATUALIZAR VISUALIZAÇÃO' 18 638 240 44 { Refresh-FinalReport } $script:Colors.Cyan)
[void](New-Button $finalReport 'ATUALIZAR POWER BI AGORA' 274 638 260 44 { Start-MainUpdate } $script:Colors.Green)

$dashboard.Add_Resize({
    $availableHeight = [math]::Max(120, $dashboard.ClientSize.Height - 530)
    $operationsGrid.Height = $availableHeight
    $flowPanel.Width = [math]::Max(700, $dashboard.ClientSize.Width - 36)
    $onboardingBar.Width = [math]::Max(700, $dashboard.ClientSize.Width - 36)
    $dashboardClockPanel.Width = [math]::Max(700, $dashboard.ClientSize.Width - 36)
    $statusGrid.Width = [math]::Max(700, $dashboard.ClientSize.Width - 36)
    $actionGrid.Width = [math]::Max(700, $dashboard.ClientSize.Width - 36)
    $operationsGrid.Width = [math]::Max(700, $dashboard.ClientSize.Width - 36)
    $guideButton.Left = $onboardingBar.ClientSize.Width - $guideButton.Width - 8
})

[void](New-Label $automation 'CONTROLE DA ROTINA' 18 22 400 28 12 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
[void](New-Label $automation 'Inicie, pause ou retome as tarefas agendadas do Windows.' 18 52 650 24 9 $script:Colors.Muted)
[void](New-Button $automation 'INICIAR PARCIAL AGORA' 18 92 235 50 { Start-MainUpdate } $script:Colors.Green)
[void](New-Button $automation 'POWER BI — PLANILHA MANUAL' 271 92 235 50 { Start-ManualPowerBIUpdate } $script:Colors.Cyan 'Escolhe um XLSX já baixado e executa somente Power BI e revisão.')
$script:AutomationToggleButton = New-Button $automation '[■] PAUSAR AUTOMAÇÃO' 524 92 235 50 { Toggle-AutomationState } $script:Colors.Gold 'Pausa ou continua todas as rotinas programadas, inclusive o SLA.'
[void](New-Button $automation 'ATUALIZAR STATUS' 777 92 235 50 { Refresh-Dashboard;Refresh-TerminalFromLogs } $script:Colors.Cyan)
[void](New-Label $automation 'ACESSOS E ARQUIVOS' 18 182 400 28 12 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
[void](New-Button $automation 'JMS MANUAL — EDGE' 18 224 190 46 { Open-JmsManual } $script:Colors.Red 'Abre o JMS no Edge com um perfil separado do Chrome usado pela automação.')
[void](New-Button $automation 'ABRIR POWER BI' 223 224 190 46 { $p=(Get-Paths).Pbix;if(Test-Path -LiteralPath $p){Start-Process $p}else{Show-OCoffeeMessage 'Configure primeiro o arquivo PBIX.'} } $script:Colors.Gold)
[void](New-Button $automation 'BASE ENTREGAS' 428 224 190 46 { $p=(Get-Paths).Base;if(Test-Path $p){Start-Process explorer.exe -ArgumentList ('"{0}"' -f $p)} } $script:Colors.Cyan)
[void](New-Button $automation 'BASE SLA' 633 224 190 46 { $p=(Get-Paths).SlaBase;if(Test-Path $p){Start-Process explorer.exe -ArgumentList ('"{0}"' -f $p)} } $script:Colors.Cyan)
[void](New-Button $automation 'WHATSAPP WEB' 838 224 174 46 { Start-Process 'https://web.whatsapp.com/' } $script:Colors.Green)
[void](New-Label $automation 'RELATÓRIOS' 18 314 400 28 12 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
[void](New-Button $automation 'REVISAR ÚLTIMA PARCIAL' 18 356 235 50 { Review-LatestPartial } $script:Colors.Cyan)
[void](New-Button $automation 'SLA — PLANILHA MANUAL' 271 356 235 50 { Start-ManualSlaUpdate } $script:Colors.Gold 'Escolhe o XLSX Entrega realizada (Lista) e atualiza a BD_D1 no Power BI.')
[void](New-Button $automation 'ABRIR PASTA DE PRINTS' 524 356 235 50 { if(Test-Path $script:ReportPath){Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:ReportPath)} } $script:Colors.Cyan)
[void](New-Button $automation 'ABRIR LOG COMPLETO' 777 356 235 50 { $p=Join-Path (Get-Paths).LogDir 'atualizacao.log';if(Test-Path $p){Start-Process notepad.exe -ArgumentList ('"{0}"' -f $p)}else{Show-OCoffeeMessage 'O log ainda não foi criado.'} } $script:Colors.Muted)
[void](New-Label $automation 'EXPEDIDO, MAS NÃO CHEGOU — SOMENTE O LÍDER INICIA' 18 438 650 28 12 $script:Colors.Red ([Drawing.FontStyle]::Bold))
[void](New-Button $automation 'EXECUTAR EXPEDIDO, MAS NÃO CHEGOU' 18 478 360 52 { Start-ExpedidoProcess } $script:Colors.Red 'Pergunta o horário do deslacramento, inicia a consulta e abre o cronômetro de 6 horas.')
[void](New-Button $automation 'PARAR CRONÔMETRO' 396 478 210 52 { Stop-ExpedidoTimer } $script:Colors.Gold 'Para somente o controle de prazo deste veículo.')
[void](New-Button $automation 'ABRIR RESULTADOS' 624 478 210 52 { $p=(Get-Paths).ExpedidoOutput;if(Test-Path -LiteralPath $p){Start-Process explorer.exe -ArgumentList ('"{0}"' -f $p)}else{Show-OCoffeeMessage 'Ainda não existe pasta de resultados.'} } $script:Colors.Cyan)
$script:ExpedidoTimerLabel = New-Label $automation 'CRONÔMETRO: não iniciado' 18 546 994 36 12 $script:Colors.Muted ([Drawing.FontStyle]::Bold)

[void](New-Label $configuration 'CONFIGURAÇÃO GUIADA' 18 22 420 28 12 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
[void](New-Label $configuration 'Cada botão conduz uma etapa. Nenhuma senha ou CAPTCHA é salvo no arquivo de configuração.' 18 52 900 24 9 $script:Colors.Muted)
[void](New-Button $configuration '1  ARQUIVOS E PASTAS' 18 92 235 52 { Configure-Files } $script:Colors.Cyan 'Escolha o PBIX, a pasta da base e a aba da parcial.')
[void](New-Button $configuration '2  WHATSAPP / ALERTAS' 271 92 235 52 { Configure-WhatsApp } $script:Colors.Green 'Salva grupo, WhatsApp do responsável e regra de baixo desempenho.')
[void](New-Button $configuration '3  HORÁRIOS' 524 92 235 52 { Configure-Schedules } $script:Colors.Gold 'Define em quais horários a parcial será atualizada.')
[void](New-Button $configuration '4  SLA / FEISHU' 777 92 235 52 { Configure-Sla } $script:Colors.Red 'Configura horário, histórico e grupo do SLA.')
[void](New-Button $configuration '5  EXPEDIDO / BASE E MODELO' 18 160 994 52 { Configure-Expedido } $script:Colors.Red 'Configura a sigla da base, o modelo Excel e a pasta de saída. Nunca cria agendamento.')
[void](New-Label $configuration 'MAPA DA CONFIGURAÇÃO ATIVA' 18 230 500 28 11 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
$script:ConfigSummary = New-Object Windows.Forms.TextBox
$script:ConfigSummary.Location = New-Object Drawing.Point(18, 266)
$script:ConfigSummary.Size = New-Object Drawing.Size(994, 250)
$script:ConfigSummary.Multiline = $true
$script:ConfigSummary.ReadOnly = $true
$script:ConfigSummary.BackColor = $script:Colors.Surface
$script:ConfigSummary.ForeColor = $script:Colors.Green
$script:ConfigSummary.BorderStyle = 'FixedSingle'
$script:ConfigSummary.Font = New-Object Drawing.Font('Consolas', 10)
[void](New-Button $configuration 'VERIFICAR ATUALIZAÇÃO NO GITHUB' 777 530 235 48 { Start-SoftwareUpdate } $script:Colors.Green 'Baixa a versão mais recente e preserva configurações e sessões.')
$script:ConfigSummary.ScrollBars = 'Vertical'
$configuration.Controls.Add($script:ConfigSummary)
[void](New-Button $configuration 'ABRIR ARQUIVO JSON' 18 532 210 40 { if(Test-Path $script:ConfigPath){Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:ConfigPath)} } $script:Colors.Muted)
[void](New-Button $configuration 'ATUALIZAR MAPA' 244 532 210 40 { Refresh-ConfigurationSummary } $script:Colors.Cyan)

[void](New-Label $diagnostic 'DIAGNÓSTICO DA ESTAÇÃO' 18 18 450 28 12 $script:Colors.Cyan ([Drawing.FontStyle]::Bold))
[void](New-Label $diagnostic 'Verifique rapidamente se esta máquina está pronta para executar sem assistência técnica.' 18 48 900 24 9 $script:Colors.Muted)
$script:Diagnostics = New-Object Windows.Forms.ListView
$script:Diagnostics.Location = New-Object Drawing.Point(18, 80)
$script:Diagnostics.Size = New-Object Drawing.Size(994, 230)
$script:Diagnostics.View = 'Details'
$script:Diagnostics.FullRowSelect = $true
$script:Diagnostics.GridLines = $true
$script:Diagnostics.BackColor = $script:Colors.Surface
$script:Diagnostics.ForeColor = $script:Colors.Text
$script:Diagnostics.BorderStyle = 'FixedSingle'
[void]$script:Diagnostics.Columns.Add('STATUS',100)
[void]$script:Diagnostics.Columns.Add('COMPONENTE',210)
[void]$script:Diagnostics.Columns.Add('DETALHE',650)
$diagnostic.Controls.Add($script:Diagnostics)
[void](New-Button $diagnostic 'EXECUTAR DIAGNÓSTICO' 18 324 230 42 { Run-Diagnostics } $script:Colors.Green)
[void](New-Button $diagnostic 'RECARREGAR TERMINAL' 264 324 230 42 { Refresh-TerminalFromLogs } $script:Colors.Cyan)
$script:Terminal = New-Object Windows.Forms.RichTextBox
$script:Terminal.Location = New-Object Drawing.Point(18, 380)
$script:Terminal.Size = New-Object Drawing.Size(994, 155)
$script:Terminal.BackColor = [Drawing.Color]::Black
$script:Terminal.ForeColor = $script:Colors.Green
$script:Terminal.BorderStyle = 'FixedSingle'
$script:Terminal.Font = New-Object Drawing.Font('Consolas', 9)
$script:Terminal.ReadOnly = $true
$diagnostic.Controls.Add($script:Terminal)

$script:FooterStatus = New-Label $form 'Inicializando estação...' 24 690 1040 25 9 $script:Colors.Muted
$script:FooterStatus.Dock = 'Bottom'
$script:FooterStatus.Height = 24

$refreshTimer = New-Object Windows.Forms.Timer
$refreshTimer.Interval = 15000
$refreshTimer.Add_Tick({ Refresh-Dashboard })
$refreshTimer.Start()
$expedidoTimer = New-Object Windows.Forms.Timer
$expedidoTimer.Interval = 1000
$expedidoTimer.Add_Tick({ Refresh-ExpedidoTimer })
$expedidoTimer.Start()
$form.Add_FormClosed({
    $refreshTimer.Stop(); $refreshTimer.Dispose()
    $expedidoTimer.Stop(); $expedidoTimer.Dispose()
    if ($script:InstanceCreated -and $script:InstanceMutex) {
        try { $script:InstanceMutex.ReleaseMutex() } catch {}
        $script:InstanceMutex.Dispose()
    }
})
$form.Add_KeyDown({ if($_.KeyCode -eq [Windows.Forms.Keys]::F5){Refresh-Dashboard;Refresh-TerminalFromLogs} })

Refresh-Dashboard
Refresh-TerminalFromLogs
Refresh-ExpedidoTimer
Run-Diagnostics
[void]$form.ShowDialog()
