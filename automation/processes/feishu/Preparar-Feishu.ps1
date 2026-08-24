param(
    [Parameter(Mandatory=$true)][string]$ImagePath,
    [Parameter(Mandatory=$true)][string]$GroupName,
    [Parameter(Mandatory=$true)][string]$Message
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$feishu=Get-Process Feishu -ErrorAction SilentlyContinue|Where-Object MainWindowHandle -ne 0|Select-Object -First 1
if(-not $feishu){
    $exe=Join-Path $env:LOCALAPPDATA 'Feishu\app\Feishu.exe'
    if(-not(Test-Path -LiteralPath $exe)){throw 'Feishu Desktop não encontrado.'}
    Start-Process -FilePath $exe; Start-Sleep -Seconds 8
    $feishu=Get-Process Feishu|Where-Object MainWindowHandle -ne 0|Select-Object -First 1
}
if(-not $feishu){throw 'A janela do Feishu não foi encontrada.'}
$shell=New-Object -ComObject WScript.Shell
if(-not $shell.AppActivate($feishu.Id)){throw 'Não foi possível ativar o Feishu.'}
Start-Sleep -Seconds 1
[Windows.Forms.Clipboard]::SetText($GroupName)
$shell.SendKeys('^k'); Start-Sleep -Seconds 1; $shell.SendKeys('^v'); Start-Sleep -Seconds 3; $shell.SendKeys('{ENTER}'); Start-Sleep -Seconds 3
$image=[Drawing.Image]::FromFile($ImagePath)
try{[Windows.Forms.Clipboard]::SetImage($image)}finally{$image.Dispose()}
$shell.SendKeys('^v'); Start-Sleep -Seconds 3
[Windows.Forms.Clipboard]::SetText($Message)
$shell.SendKeys('^v'); Start-Sleep -Seconds 2

