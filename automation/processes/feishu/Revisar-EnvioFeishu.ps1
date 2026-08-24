param([Parameter(Mandatory=$true)][string]$ImagePath,[Parameter(Mandatory=$true)][string]$EndDate)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$config=Get-Content -LiteralPath 'C:\oCoffe\config\gestao-kpi.json' -Raw -Encoding UTF8|ConvertFrom-Json
$group=$(if($config.slaGrupoFeishu){[string]$config.slaGrupoFeishu}else{'MA/PI - Hub/Pdd 网点管理'})
$template=$(if($config.slaMensagemFeishu){[string]$config.slaMensagemFeishu}else{"Segue o SLA de {dataFinalJms}.`r`n`r`nAtualização gerada pelo Assistente oCoffeIA"})
$date=[datetime]::ParseExact($EndDate,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
$message=$template.Replace('{dataFinalJms}',$date.ToString('dd/MM/yyyy'))
$form=New-Object Windows.Forms.Form
$form.Text='Revisar SLA para o Feishu — oCoffeIA';$form.StartPosition='CenterScreen';$form.Size=New-Object Drawing.Size(1040,760);$form.TopMost=$true
$form.BackColor=[Drawing.Color]::FromArgb(28,28,30);$form.ForeColor=[Drawing.Color]::White;$form.Font=New-Object Drawing.Font('Segoe UI',10)
$title=New-Object Windows.Forms.Label;$title.Text='Confira o SLA antes de reportar';$title.Font=New-Object Drawing.Font('Segoe UI Semibold',20);$title.Location=New-Object Drawing.Point(22,16);$title.AutoSize=$true;$form.Controls.Add($title)
$notice=New-Object Windows.Forms.Label;$notice.Text='Nada será enviado sem uma segunda confirmação no Feishu.';$notice.Location=New-Object Drawing.Point(25,58);$notice.AutoSize=$true;$notice.ForeColor=[Drawing.Color]::Gold;$form.Controls.Add($notice)
$target=New-Object Windows.Forms.Label;$target.Text="Grupo: $group    |    SLA: $($date.ToString('dd/MM/yyyy'))";$target.Location=New-Object Drawing.Point(25,88);$target.AutoSize=$true;$form.Controls.Add($target)
$picture=New-Object Windows.Forms.PictureBox;$picture.Location=New-Object Drawing.Point(25,120);$picture.Size=New-Object Drawing.Size(970,430);$picture.BorderStyle='FixedSingle';$picture.SizeMode='Zoom';$picture.Image=[Drawing.Image]::FromFile($ImagePath);$form.Controls.Add($picture)
$box=New-Object Windows.Forms.TextBox;$box.Location=New-Object Drawing.Point(25,580);$box.Size=New-Object Drawing.Size(650,85);$box.Multiline=$true;$box.Text=$message;$form.Controls.Add($box)
$confirm=New-Object Windows.Forms.Button;$confirm.Text='Preparar no Feishu';$confirm.Location=New-Object Drawing.Point(700,580);$confirm.Size=New-Object Drawing.Size(145,48);$confirm.BackColor=[Drawing.Color]::FromArgb(0,145,90);$form.Controls.Add($confirm)
$cancel=New-Object Windows.Forms.Button;$cancel.Text='Cancelar';$cancel.Location=New-Object Drawing.Point(855,580);$cancel.Size=New-Object Drawing.Size(140,48);$form.Controls.Add($cancel)
$status=New-Object Windows.Forms.Label;$status.Location=New-Object Drawing.Point(25,680);$status.Size=New-Object Drawing.Size(950,25);$form.Controls.Add($status)
$cancel.Add_Click({$form.Close()})
$confirm.Add_Click({
    $confirm.Enabled=$false;$status.Text='Preparando imagem e mensagem no Feishu...';$form.Refresh()
    try{
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\oCoffe\processes\feishu\Preparar-Feishu.ps1' -ImagePath $ImagePath -GroupName $group -Message $box.Text
        if($LASTEXITCODE -ne 0){throw "Preparação terminou com código $LASTEXITCODE."}
        $answer=[Windows.Forms.MessageBox]::Show("Confira no Feishu se o grupo aberto é:`r`n$group`r`n`r`nA imagem e a mensagem estão corretas?",'Confirmação final do SLA',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)
        if($answer -eq [Windows.Forms.DialogResult]::Yes){
            $feishu=Get-Process Feishu|Where-Object MainWindowHandle -ne 0|Select-Object -First 1;$shell=New-Object -ComObject WScript.Shell;[void]$shell.AppActivate($feishu.Id);Start-Sleep -Milliseconds 500;$shell.SendKeys('{ENTER}');$status.Text='SLA enviado ao Feishu.';Start-Sleep -Seconds 1;$form.Close()
        }else{$status.Text='Envio cancelado. O conteúdo ficou preparado no Feishu para revisão.';$confirm.Enabled=$true}
    }catch{$status.Text="Falha: $($_.Exception.Message)";$confirm.Enabled=$true;[Windows.Forms.MessageBox]::Show($_.Exception.Message,'oCoffeIA')|Out-Null}
})
$form.Add_FormClosed({if($picture.Image){$picture.Image.Dispose()}})
[void]$form.ShowDialog()

