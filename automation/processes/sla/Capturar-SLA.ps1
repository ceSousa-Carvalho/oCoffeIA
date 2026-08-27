param([Parameter(Mandatory=$true)][string]$EndDate)
$ErrorActionPreference='Stop';Add-Type -AssemblyName System.Drawing
$reportDir='C:\oCoffe\reports';New-Item -ItemType Directory -Path $reportDir -Force|Out-Null
$pbi=Get-Process PBIDesktop|Where-Object MainWindowTitle -like '*Gestão de KPI*'|Select-Object -First 1;if(-not $pbi){throw 'Power BI não encontrado.'}
$endDateValue=[datetime]::ParseExact($EndDate,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
$dateHelper='C:\oCoffe\tools\PowerBI-DateRange.ps1';if(-not(Test-Path -LiteralPath $dateHelper)){throw "Componente de datas não encontrado: $dateHelper"};. $dateHelper
$configFile='C:\oCoffe\config\gestao-kpi.json';$slaPage='SLA - VENCIMENTO';if(Test-Path -LiteralPath $configFile){$config=Get-Content -LiteralPath $configFile -Raw -Encoding UTF8|ConvertFrom-Json;if(-not[string]::IsNullOrWhiteSpace($config.slaPaginaPowerBi)){$slaPage=[string]$config.slaPaginaPowerBi}}
Add-Type @'
using System;using System.Runtime.InteropServices;public static class SlaCapture{[StructLayout(LayoutKind.Sequential)]public struct RECT{public int Left,Top,Right,Bottom;}[DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out RECT r);[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);[DllImport("user32.dll")]public static extern bool PrintWindow(IntPtr h,IntPtr d,uint f);}
'@
[SlaCapture]::ShowWindow($pbi.MainWindowHandle,3)|Out-Null;Start-Sleep -Seconds 2
$verifiedDates=$null
for($attempt=1;$attempt -le 6 -and -not $verifiedDates;$attempt++){
    Select-PowerBIReportPage -WindowHandle $pbi.MainWindowHandle -PageName $slaPage
    Start-Sleep -Seconds 3
    try{$verifiedDates=Set-PowerBIDateRangeVerified -WindowHandle $pbi.MainWindowHandle -Date $endDateValue -Context 'SLA antes da captura'}catch{
        if($attempt -eq 6){throw}
        Start-Sleep -Seconds 2
    }
}
$rect=New-Object SlaCapture+RECT;[void][SlaCapture]::GetWindowRect($pbi.MainWindowHandle,[ref]$rect)
$shell=New-Object -ComObject WScript.Shell;[void]$shell.AppActivate($pbi.Id);$shell.SendKeys('{ESC}');Start-Sleep -Seconds 1
$bitmap=[Drawing.Bitmap]::new($rect.Right-$rect.Left,$rect.Bottom-$rect.Top);$graphics=[Drawing.Graphics]::FromImage($bitmap)
$image=Join-Path $reportDir "sla-$($EndDate.Replace('-',''))-$(Get-Date -Format 'HHmmss').png"
try{$hdc=$graphics.GetHdc();try{if(-not[SlaCapture]::PrintWindow($pbi.MainWindowHandle,$hdc,2)){throw 'Falha ao capturar Power BI.'}}finally{$graphics.ReleaseHdc($hdc)};$area=[Drawing.Rectangle]::FromLTRB([int]($bitmap.Width*.023),[int]($bitmap.Height*.120),[int]($bitmap.Width*.835),[int]($bitmap.Height*.964));$cropped=$bitmap.Clone($area,$bitmap.PixelFormat);try{$cropped.Save($image,[Drawing.Imaging.ImageFormat]::Png)}finally{$cropped.Dispose()}}finally{$graphics.Dispose();$bitmap.Dispose()}
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\oCoffe\processes\feishu\Revisar-EnvioFeishu.ps1`" -ImagePath `"$image`" -EndDate `"$EndDate`""
