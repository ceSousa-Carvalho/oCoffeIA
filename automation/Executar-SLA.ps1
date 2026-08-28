param([switch]$Force)
$ErrorActionPreference='Stop';$root='C:\oCoffe';$log='C:\oCoffe\sla.log'
function Log($m){Add-Content -LiteralPath $log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"}
try{
    $config=Get-Content -LiteralPath (Join-Path $root 'config\gestao-kpi.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $slaLogDir=[Environment]::ExpandEnvironmentVariables($(if($config.logDir){[string]$config.logDir}else{'C:\Gestão de KPI_Operacional_v2\Automacao'}))
    $stateFile=Join-Path $slaLogDir 'ultimo-sla-processado.json'
    if((Test-Path -LiteralPath $stateFile)-and-not $Force){$state=Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8|ConvertFrom-Json;if([string]$state.executionDate -eq (Get-Date -Format 'yyyy-MM-dd')){Log "SLA já atualizado hoje em $($state.completedAt).";exit 0}}
    $forceArg=$(if($Force){'-Force'}else{''})
    & node.exe (Join-Path $root 'browser\jms-sla-download.js');if($LASTEXITCODE){throw "Download SLA falhou: $LASTEXITCODE"}
    & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File (Join-Path $root 'processes\sla\Atualizar-SLA.ps1') $forceArg
    if($LASTEXITCODE -eq 10){Log 'SLA já atualizado hoje.';exit 0};if($LASTEXITCODE){throw "Atualização SLA falhou: $LASTEXITCODE"}
    Log 'SLA diário concluído; Power BI atualizado e salvo.'
}catch{Log "ERRO: $($_.Exception.Message)";exit 1}
