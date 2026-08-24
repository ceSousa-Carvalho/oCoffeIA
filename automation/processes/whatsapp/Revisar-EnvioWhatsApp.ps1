param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,
    [string]$ReportTime
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$configFile = 'C:\oCoffe\config\gestao-kpi.json'
$nodeScript = 'C:\oCoffe\browser\whatsapp-send.js'
$logFile = 'C:\oCoffe\whatsapp.log'
$groupName = 'Entregadores J&T - THE'
$messageTemplate = "@all Segue a parcial das {horario}.`r`n`r`nAtualização gerada pelo Assistente oCoffeIA"

if (-not (Test-Path -LiteralPath $ImagePath)) { throw "Captura não encontrada: $ImagePath" }
if (Test-Path -LiteralPath $configFile) {
    $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace($config.nomeGrupoWhatsApp)) { $groupName = $config.nomeGrupoWhatsApp }
    if (-not [string]::IsNullOrWhiteSpace($config.mensagem)) { $messageTemplate = $config.mensagem }
}
$reportDate = $null
if (-not [string]::IsNullOrWhiteSpace($ReportTime)) {
    $parsedDate = [datetime]::MinValue
    if ([datetime]::TryParse($ReportTime, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsedDate)) {
        $reportDate = $parsedDate
    }
}
if (-not $reportDate) {
    $metadataPath = [IO.Path]::ChangeExtension($ImagePath, '.json')
    if (Test-Path -LiteralPath $metadataPath) {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $parsedDate = [datetime]::MinValue
        if ([datetime]::TryParse([string]$metadata.reportTime, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsedDate)) {
            $reportDate = $parsedDate
        }
    }
}
if (-not $reportDate) { $reportDate = (Get-Item -LiteralPath $ImagePath).LastWriteTime }
$displayTime = if ($reportDate.Minute -eq 0) { $reportDate.ToString('HH') + 'h' } else { $reportDate.ToString('HH') + 'h' + $reportDate.ToString('mm') }
$message = $messageTemplate.Replace('{horario}', $displayTime).Replace('{hora}', $reportDate.ToString('HH'))
$message = $message -replace '\r?\n', "`r`n"

$form = New-Object Windows.Forms.Form
$form.Text = 'Revisar parcial — oCoffeIA'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object Drawing.Size(1040, 760)
$form.MinimumSize = New-Object Drawing.Size(850, 650)
$form.TopMost = $true
$form.BackColor = [Drawing.Color]::FromArgb(28, 28, 30)
$form.ForeColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

$title = New-Object Windows.Forms.Label
$title.Text = 'Confira antes de reportar'
$title.Font = New-Object Drawing.Font('Segoe UI Semibold', 20)
$title.Location = New-Object Drawing.Point(22, 16)
$title.AutoSize = $true
$form.Controls.Add($title)

$notice = New-Object Windows.Forms.Label
$notice.Text = 'Nada será enviado até você clicar em “Confirmar e enviar”.'
$notice.Location = New-Object Drawing.Point(25, 57)
$notice.AutoSize = $true
$notice.ForeColor = [Drawing.Color]::Gold
$form.Controls.Add($notice)

$groupLabel = New-Object Windows.Forms.Label
$groupLabel.Text = "Grupo: $groupName    |    Relatório baixado: $($reportDate.ToString('dd/MM/yyyy HH:mm'))"
$groupLabel.Location = New-Object Drawing.Point(25, 88)
$groupLabel.AutoSize = $true
$form.Controls.Add($groupLabel)

$picture = New-Object Windows.Forms.PictureBox
$picture.Location = New-Object Drawing.Point(25, 120)
$picture.Size = New-Object Drawing.Size(970, 430)
$picture.Anchor = 'Top,Bottom,Left,Right'
$picture.BorderStyle = 'FixedSingle'
$picture.SizeMode = 'Zoom'
$picture.Image = [Drawing.Image]::FromFile($ImagePath)
$form.Controls.Add($picture)

$messageLabel = New-Object Windows.Forms.Label
$messageLabel.Text = 'Mensagem (você pode corrigir antes do envio):'
$messageLabel.Location = New-Object Drawing.Point(25, 565)
$messageLabel.Anchor = 'Bottom,Left'
$messageLabel.AutoSize = $true
$form.Controls.Add($messageLabel)

$messageBox = New-Object Windows.Forms.TextBox
$messageBox.Location = New-Object Drawing.Point(25, 590)
$messageBox.Size = New-Object Drawing.Size(650, 82)
$messageBox.Anchor = 'Bottom,Left,Right'
$messageBox.Multiline = $true
$messageBox.ScrollBars = 'Vertical'
$messageBox.Text = $message
$form.Controls.Add($messageBox)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(25, 684)
$status.Size = New-Object Drawing.Size(650, 25)
$status.Anchor = 'Bottom,Left,Right'
$status.ForeColor = [Drawing.Color]::LightGray
$form.Controls.Add($status)

$confirm = New-Object Windows.Forms.Button
$confirm.Text = 'Confirmar e enviar'
$confirm.Location = New-Object Drawing.Point(700, 590)
$confirm.Size = New-Object Drawing.Size(145, 48)
$confirm.Anchor = 'Bottom,Right'
$confirm.BackColor = [Drawing.Color]::FromArgb(0, 145, 90)
$confirm.ForeColor = [Drawing.Color]::White
$confirm.FlatStyle = 'Flat'
$form.Controls.Add($confirm)

$cancel = New-Object Windows.Forms.Button
$cancel.Text = 'Cancelar'
$cancel.Location = New-Object Drawing.Point(855, 590)
$cancel.Size = New-Object Drawing.Size(140, 48)
$cancel.Anchor = 'Bottom,Right'
$cancel.BackColor = [Drawing.Color]::FromArgb(65, 65, 68)
$cancel.ForeColor = [Drawing.Color]::White
$cancel.FlatStyle = 'Flat'
$form.Controls.Add($cancel)

$cancel.Add_Click({
    Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Envio cancelado pelo usuário: $ImagePath"
    $form.Close()
})

$script:sendJob = $null
$sendTimer = New-Object Windows.Forms.Timer
$sendTimer.Interval = 500
$sendTimer.Add_Tick({
    if (-not $script:sendJob -or $script:sendJob.State -in 'Running', 'NotStarted') { return }

    $sendTimer.Stop()
    $result = Receive-Job -Job $script:sendJob -ErrorAction SilentlyContinue | Select-Object -Last 1
    $jobState = $script:sendJob.State
    $jobReason = [string]$script:sendJob.ChildJobs[0].JobStateInfo.Reason
    Remove-Job -Job $script:sendJob -Force -ErrorAction SilentlyContinue
    $script:sendJob = $null

    if ($jobState -eq 'Completed' -and $result.Success) {
        $status.Text = 'Parcial enviada com sucesso.'
        $status.ForeColor = [Drawing.Color]::LightGreen
        $form.Refresh()
        Start-Sleep -Milliseconds 700
        $form.Hide()
        $form.Close()
        return
    }

    $detail = if ($result -and -not [string]::IsNullOrWhiteSpace([string]$result.Detail)) {
        [string]$result.Detail
    } elseif (-not [string]::IsNullOrWhiteSpace($jobReason)) {
        $jobReason
    } else {
        'Consulte C:\oCoffe\whatsapp.log.'
    }
    $status.Text = "Falha no envio: $detail"
    $status.ForeColor = [Drawing.Color]::OrangeRed
    [Windows.Forms.MessageBox]::Show("Não foi possível enviar.`r`n`r`n$detail", 'oCoffeIA') | Out-Null
    $confirm.Enabled = $true
    $cancel.Enabled = $true
})

$confirm.Add_Click({
    if ([string]::IsNullOrWhiteSpace($messageBox.Text)) {
        [Windows.Forms.MessageBox]::Show('A mensagem não pode ficar vazia.', 'oCoffeIA') | Out-Null
        return
    }
    $confirm.Enabled = $false
    $cancel.Enabled = $false
    $status.Text = 'Abrindo o WhatsApp Web e preparando o envio...'
    $status.ForeColor = [Drawing.Color]::Gold
    $form.Refresh()
    try {
        $nodePath = (Get-Command node.exe -ErrorAction Stop).Source
        $script:sendJob = Start-Job -ScriptBlock {
            param($NodePath, $NodeScript, $Image, $Group, $Message)
            $sendMutex = [Threading.Mutex]::new($false, 'Global\oCoffeIA-WhatsApp-Envio')
            $ownsMutex = $false
            try {
                try { $ownsMutex = $sendMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
                if (-not $ownsMutex) { throw 'Já existe outro envio do oCoffeIA em andamento.' }
                $nodeOutput = (& $NodePath $NodeScript $Image $Group $Message 2>&1 | Out-String).Trim()
                $nodeExitCode = $LASTEXITCODE
                if ($nodeExitCode -ne 0) {
                    $detail = if ([string]::IsNullOrWhiteSpace($nodeOutput)) { 'Consulte C:\oCoffe\whatsapp.log.' } else { $nodeOutput }
                    throw "O WhatsApp terminou com código $nodeExitCode.`r`n`r`n$detail"
                }
                [pscustomobject]@{ Success = $true; Detail = '' }
            } catch {
                [pscustomobject]@{ Success = $false; Detail = $_.Exception.Message }
            } finally {
                if ($ownsMutex) { $sendMutex.ReleaseMutex() }
                $sendMutex.Dispose()
            }
        } -ArgumentList $nodePath, $nodeScript, $ImagePath, $groupName, $messageBox.Text
        $sendTimer.Start()
    } catch {
        $status.Text = "Falha no envio: $($_.Exception.Message)"
        $status.ForeColor = [Drawing.Color]::OrangeRed
        [Windows.Forms.MessageBox]::Show("Não foi possível enviar.`r`n`r`n$($_.Exception.Message)", 'oCoffeIA') | Out-Null
        $confirm.Enabled = $true
        $cancel.Enabled = $true
    }
})

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:sendJob -and $script:sendJob.State -in 'Running', 'NotStarted') {
        $eventArgs.Cancel = $true
        $status.Text = 'O envio está em andamento. Aguarde a conclusão.'
        $status.ForeColor = [Drawing.Color]::Gold
    }
})
$form.Add_FormClosed({
    $sendTimer.Stop()
    $sendTimer.Dispose()
    if ($script:sendJob) {
        Stop-Job -Job $script:sendJob -ErrorAction SilentlyContinue
        Remove-Job -Job $script:sendJob -Force -ErrorAction SilentlyContinue
        $script:sendJob = $null
    }
    if ($picture.Image) { $picture.Image.Dispose() }
})
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()






