param(
    [Parameter(Position = 0)]
    [ValidateSet('agora', 'status', 'pausar', 'ativar', 'log', 'ajuda')]
    [string]$Comando = 'ajuda'
)

$task = Get-ScheduledTask | Where-Object { $_.TaskName -like 'JMS -*KPI' } | Select-Object -First 1
$configFile = 'C:\oCoffe\config\gestao-kpi.json'
$logDir = 'C:\Gestão de KPI_Operacional_v2\Automacao'
if (Test-Path -LiteralPath $configFile) {
    try {
        $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.logDir) {
            $logDir = [Environment]::ExpandEnvironmentVariables([string]$config.logDir)
        }
    } catch {
        Write-Warning "Não foi possível ler a configuração: $($_.Exception.Message)"
    }
}
$log = Join-Path $logDir 'atualizacao.log'

switch ($Comando) {
    'agora' {
        if (-not $task) { throw 'A tarefa do oCoffe não está instalada.' }
        Start-ScheduledTask -TaskName $task.TaskName
        Write-Host 'oCoffe iniciado.' -ForegroundColor Green
    }
    'status' {
        if (-not $task) { throw 'A tarefa do oCoffe não está instalada.' }
        $info = Get-ScheduledTaskInfo -TaskName $task.TaskName
        Write-Host "Estado: $($task.State)"
        Write-Host "Última execução: $($info.LastRunTime)"
        Write-Host "Próxima execução: $($info.NextRunTime)"
        Write-Host "Último resultado: $($info.LastTaskResult)"
    }
    'pausar' {
        if (-not $task) { throw 'A tarefa do oCoffe não está instalada.' }
        Disable-ScheduledTask -TaskName $task.TaskName | Out-Null
        Write-Host 'oCoffe pausado.' -ForegroundColor Yellow
    }
    'ativar' {
        if (-not $task) { throw 'A tarefa do oCoffe não está instalada.' }
        Enable-ScheduledTask -TaskName $task.TaskName | Out-Null
        Write-Host 'oCoffe ativado.' -ForegroundColor Green
    }
    'log' {
        if (Test-Path -LiteralPath $log) {
            Get-Content -LiteralPath $log -Tail 20
        } else {
            Write-Host 'O log ainda não foi criado.'
        }
    }
    default {
        Write-Host 'Comandos do oCoffe:' -ForegroundColor Cyan
        Write-Host '  ocoffe agora   - executar imediatamente'
        Write-Host '  ocoffe status  - mostrar o estado'
        Write-Host '  ocoffe pausar  - pausar a rotina horária'
        Write-Host '  ocoffe ativar  - reativar a rotina horária'
        Write-Host '  ocoffe log     - mostrar as últimas ocorrências'
    }
}






