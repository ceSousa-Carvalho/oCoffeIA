param([Parameter(Mandatory = $true)][string]$ResultPath)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$result = Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
$alerts = @($result.alertas)
if ($alerts.Count -eq 0) { exit 0 }
$phone = ([string]$result.whatsappResponsavel) -replace '\D', ''
$nodeScript = 'C:\oCoffe\browser\whatsapp-direct-send.js'
$logFile = 'C:\oCoffe\desempenho.log'

$lines = foreach ($alert in $alerts) {
    "• $($alert.entregador): $($alert.percentual)% ($($alert.entregues)/$($alert.pedidos)), saída $($alert.saida), $($alert.horasDeRota)h de rota"
}
$message = "Alerta de acompanhamento de entregas - $(Get-Date -Format 'dd/MM HH:mm')`r`n`r`n" + ($lines -join "`r`n") + "`r`n`r`nAtualização gerada pelo Assistente oCoffeIA"

$form = New-Object Windows.Forms.Form
$form.Text = 'Revisar alerta de desempenho — oCoffeIA'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object Drawing.Size(860, 620)
$form.MinimumSize = New-Object Drawing.Size(760, 540)
$form.TopMost = $true
$form.BackColor = [Drawing.Color]::FromArgb(28, 28, 30)
$form.ForeColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

$title = New-Object Windows.Forms.Label
$title.Text = 'Atenção: rota abaixo do ritmo configurado'
$title.Font = New-Object Drawing.Font('Segoe UI Semibold', 18)
$title.Location = New-Object Drawing.Point(22, 18)
$title.AutoSize = $true
$form.Controls.Add($title)

$notice = New-Object Windows.Forms.Label
$notice.Text = 'Nada será enviado até você revisar e clicar em “Confirmar e enviar”.'
$notice.Location = New-Object Drawing.Point(25, 58)
$notice.AutoSize = $true
$notice.ForeColor = [Drawing.Color]::Gold
$form.Controls.Add($notice)

$grid = New-Object Windows.Forms.ListView
$grid.Location = New-Object Drawing.Point(25, 92)
$grid.Size = New-Object Drawing.Size(790, 230)
$grid.Anchor = 'Top,Left,Right'
$grid.View = 'Details'; $grid.FullRowSelect = $true; $grid.GridLines = $true
$grid.BackColor = [Drawing.Color]::FromArgb(38, 38, 41); $grid.ForeColor = [Drawing.Color]::White
[void]$grid.Columns.Add('ENTREGADOR', 335); [void]$grid.Columns.Add('SAÍDA', 130); [void]$grid.Columns.Add('ENTREGUES', 90); [void]$grid.Columns.Add('TOTAL', 70); [void]$grid.Columns.Add('%', 70)
foreach ($alert in $alerts) {
    $item = New-Object Windows.Forms.ListViewItem([string]$alert.entregador)
    [void]$item.SubItems.Add([string]$alert.saida); [void]$item.SubItems.Add([string]$alert.entregues); [void]$item.SubItems.Add([string]$alert.pedidos); [void]$item.SubItems.Add("$($alert.percentual)%")
    [void]$grid.Items.Add($item)
}
$form.Controls.Add($grid)

$messageBox = New-Object Windows.Forms.TextBox
$messageBox.Location = New-Object Drawing.Point(25, 342)
$messageBox.Size = New-Object Drawing.Size(790, 135)
$messageBox.Anchor = 'Top,Bottom,Left,Right'
$messageBox.Multiline = $true; $messageBox.ScrollBars = 'Vertical'; $messageBox.Text = $message
$form.Controls.Add($messageBox)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(25, 490); $status.Size = New-Object Drawing.Size(500, 30); $status.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($status)

$confirm = New-Object Windows.Forms.Button
$confirm.Text = 'Confirmar e enviar'; $confirm.Location = New-Object Drawing.Point(535, 500); $confirm.Size = New-Object Drawing.Size(135, 45); $confirm.Anchor = 'Bottom,Right'; $confirm.BackColor = [Drawing.Color]::FromArgb(0,145,90); $confirm.FlatStyle = 'Flat'
$form.Controls.Add($confirm)
$cancel = New-Object Windows.Forms.Button
$cancel.Text = 'Cancelar'; $cancel.Location = New-Object Drawing.Point(680, 500); $cancel.Size = New-Object Drawing.Size(135,45); $cancel.Anchor = 'Bottom,Right'; $cancel.BackColor = [Drawing.Color]::FromArgb(65,65,68); $cancel.FlatStyle = 'Flat'
$form.Controls.Add($cancel)

$cancel.Add_Click({ Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Alerta cancelado pelo usuário."; $form.Close() })
$confirm.Add_Click({
    $confirm.Enabled = $false; $cancel.Enabled = $false; $status.Text = 'Abrindo o WhatsApp Web...'; $form.Refresh()
    $mutex = [Threading.Mutex]::new($false, 'Global\oCoffeIA-WhatsApp-Envio'); $owns = $false
    try {
        try { $owns = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owns = $true }
        if (-not $owns) { throw 'Já existe outro envio do oCoffeIA em andamento.' }
        $output = (& node.exe $nodeScript $phone $messageBox.Text 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw $(if($output){$output}else{'Falha no WhatsApp Web.'}) }
        $status.Text = 'Alerta enviado com sucesso.'; $form.Refresh(); Start-Sleep -Milliseconds 700; $form.Close()
    } catch {
        $status.Text = "Falha: $($_.Exception.Message)"; $status.ForeColor = [Drawing.Color]::OrangeRed
        [void][Windows.Forms.MessageBox]::Show("Não foi possível enviar.`r`n`r`n$($_.Exception.Message)", 'oCoffeIA')
        $confirm.Enabled = $true; $cancel.Enabled = $true
    } finally { if($owns){$mutex.ReleaseMutex()}; $mutex.Dispose() }
})

[void]$form.ShowDialog()

