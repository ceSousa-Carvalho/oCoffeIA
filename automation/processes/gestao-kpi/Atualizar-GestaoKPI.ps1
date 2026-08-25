$ErrorActionPreference = 'Stop'

$configFile = 'C:\oCoffe\config\gestao-kpi.json'
$projectDir = 'C:\Gestão de KPI_Operacional_v2'
$downloads = Join-Path $env:USERPROFILE 'Downloads'
$baseDir = Join-Path $projectDir 'Base_Gestão_de_pedidos_'
$pbix = Join-Path $projectDir 'Gestão de KPI.pbix'
$logDir = Join-Path $projectDir 'Automacao'
if (Test-Path -LiteralPath $configFile) {
    $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace($config.downloads)) { $downloads = [Environment]::ExpandEnvironmentVariables([string]$config.downloads) }
    if (-not [string]::IsNullOrWhiteSpace($config.baseDir)) { $baseDir = [Environment]::ExpandEnvironmentVariables([string]$config.baseDir) }
    if (-not [string]::IsNullOrWhiteSpace($config.powerBi)) { $pbix = [Environment]::ExpandEnvironmentVariables([string]$config.powerBi) }
    if (-not [string]::IsNullOrWhiteSpace($config.logDir)) { $logDir = [Environment]::ExpandEnvironmentVariables([string]$config.logDir) }
}
$logFile = Join-Path $logDir 'atualizacao.log'
$stateFile = Join-Path $logDir 'ultimo-arquivo.txt'
$pattern = 'Exportar carta de porte de entrega*.xlsx'

New-Item -ItemType Directory -Path $baseDir, $logDir -Force | Out-Null

function Write-Log([string]$message) {
    Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message"
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class oCoffeWindow {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr processId);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
}
'@

function Set-ForegroundWindow([IntPtr]$Handle) {
    $foreground = [oCoffeWindow]::GetForegroundWindow()
    $foregroundThread = [oCoffeWindow]::GetWindowThreadProcessId($foreground, [IntPtr]::Zero)
    $currentThread = [oCoffeWindow]::GetCurrentThreadId()
    [oCoffeWindow]::AttachThreadInput($currentThread, $foregroundThread, $true) | Out-Null
    try {
        [oCoffeWindow]::ShowWindow($Handle, 9) | Out-Null
        [oCoffeWindow]::BringWindowToTop($Handle) | Out-Null
        [oCoffeWindow]::SetForegroundWindow($Handle) | Out-Null
        return [oCoffeWindow]::GetForegroundWindow() -eq $Handle
    } finally {
        [oCoffeWindow]::AttachThreadInput($currentThread, $foregroundThread, $false) | Out-Null
    }
}

function Invoke-PowerBISchemaAndDataRefresh($PowerBIProcess) {
    $engine = Get-CimInstance Win32_Process |
        Where-Object { $_.Name -eq 'msmdsrv.exe' -and $_.ParentProcessId -eq $PowerBIProcess.Id } |
        Select-Object -First 1
    if (-not $engine) { throw 'Mecanismo de dados do Power BI não encontrado.' }

    $dataPath = [regex]::Match($engine.CommandLine, '-s\s+"([^"]+)"').Groups[1].Value
    $port = (Get-Content -LiteralPath (Join-Path $dataPath 'msmdsrv.port.txt') -Encoding Unicode -Raw).Trim([char]0).Trim()
    $powerBiBin = Split-Path $PowerBIProcess.Path
    Add-Type -Path (Join-Path $powerBiBin 'Microsoft.AnalysisServices.Server.Core.dll')
    Add-Type -Path (Join-Path $powerBiBin 'Microsoft.AnalysisServices.Server.Tabular.dll')

    $server = [Microsoft.AnalysisServices.Tabular.Server]::new()
    $server.Connect("localhost:$port")
    try {
        $model = $server.Databases[0].Model
        $table = $model.Tables.Find('Base_Gestão_de_pedidos_')
        if (-not $table) { throw 'Tabela Base_Gestão_de_pedidos_ não encontrada no modelo.' }
        $table.RequestRefresh([Microsoft.AnalysisServices.Tabular.RefreshType]::Full)
        $model.RequestRefresh([Microsoft.AnalysisServices.Tabular.RefreshType]::Calculate)
        $model.SaveChanges()
    } finally {
        $server.Disconnect()
    }
}

try {
    $downloadCandidate = Get-ChildItem -LiteralPath $downloads -Filter $pattern -File |
        Where-Object { $_.LastWriteTime -ge (Get-Date).AddHours(-2) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    $baseCandidate = Get-ChildItem -LiteralPath $baseDir -Filter $pattern -File |
        Where-Object { $_.LastWriteTime -ge (Get-Date).AddHours(-2) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    $candidate = @($downloadCandidate, $baseCandidate) |
        Where-Object { $_ } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $candidate) {
        Write-Log 'Nenhuma exportação recente encontrada em Downloads ou na pasta do BI.'
        exit 2
    }

    if ($candidate.Length -lt 1024) {
        throw "Arquivo novo inválido ou incompleto: $($candidate.FullName)"
    }

    $signature = [System.IO.File]::ReadAllBytes($candidate.FullName)[0..1]
    if ($signature[0] -ne 0x50 -or $signature[1] -ne 0x4B) {
        throw "O arquivo não possui uma estrutura XLSX válida: $($candidate.FullName)"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($candidate.FullName)
    try {
        $workbookEntry = $archive.GetEntry('xl/workbook.xml')
        $sheetEntry = $archive.GetEntry('xl/worksheets/sheet1.xml')
        if (-not $workbookEntry -or -not $sheetEntry) {
            throw 'O relatório XLSX não contém a estrutura esperada pelo Power BI.'
        }
        $reader = [System.IO.StreamReader]::new($workbookEntry.Open())
        try { $workbookXml = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $reader = [System.IO.StreamReader]::new($sheetEntry.Open())
        try { $sheetXml = [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
        # O JMS pode truncar o nome da aba (por exemplo, "Exportar carta de po").
        # Os cabeçalhos são a identificação estável do relatório exportado.
        $sheetText = $sheetXml.DocumentElement.InnerText
        $isPortuguese = $sheetText -match 'Número de pedido JMS'
        $isChinese = $sheetText -match '运单编号'
        if (-not $isPortuguese -and -not $isChinese) {
            throw 'O relatório JMS possui uma estrutura ou idioma ainda não reconhecido. A base anterior foi preservada.'
        }
        $reportLanguage = if ($isPortuguese) { 'português' } else { 'chinês' }
        Write-Log "Relatório validado no idioma: $reportLanguage."
    } finally {
        $archive.Dispose()
    }

    if ($workbookXml -match 'name="Exportar carta de po"') {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        try {
            $workbook = $excel.Workbooks.Open($candidate.FullName)
            $workbook.Worksheets.Item(1).Name = 'Exportar carta de porte de entr'
            $workbook.Save()
            $workbook.Close($false)
        } finally {
            $excel.Quit()
        }
        $candidate = Get-Item -LiteralPath $candidate.FullName
        Write-Log 'Nome truncado da aba normalizado pelo Excel para compatibilidade com o PBIX antigo.'
    }

    $candidateId = "$($candidate.Name)|$($candidate.Length)|$($candidate.LastWriteTimeUtc.Ticks)"
    if ((Test-Path -LiteralPath $stateFile) -and ((Get-Content -LiteralPath $stateFile -Raw).Trim() -eq $candidateId)) {
        Write-Log "Arquivo já processado anteriormente: $($candidate.Name)"
        exit 3
    }

    if ($candidate.DirectoryName -ne $baseDir) {
        $staging = Join-Path $baseDir ('.novo-' + [guid]::NewGuid().ToString('N') + '.xlsx')
        Copy-Item -LiteralPath $candidate.FullName -Destination $staging

        $copied = Get-Item -LiteralPath $staging
        if ($copied.Length -ne $candidate.Length) {
            Remove-Item -LiteralPath $staging -Force
            throw 'A cópia de validação ficou com tamanho diferente do arquivo baixado.'
        }

        Get-ChildItem -LiteralPath $baseDir -Filter '*.xlsx' -File |
            Where-Object { $_.FullName -ne $staging } |
            Remove-Item -Force

        $destination = Join-Path $baseDir $candidate.Name
        Move-Item -LiteralPath $staging -Destination $destination
        Write-Log "Base substituída com sucesso: $destination"
    } else {
        Write-Log "Chrome já salvou a base diretamente na pasta do BI: $($candidate.FullName)"
    }

    $pbi = Get-Process PBIDesktop -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -like '*Gestão de KPI*' } |
        Select-Object -First 1

    if (-not $pbi) {
        Start-Process -FilePath $pbix
        Write-Log 'Power BI iniciado; aguardando a janela Gestão de KPI ficar pronta.'
        $deadline = (Get-Date).AddMinutes(10)
        $nextWaitLog = Get-Date
        do {
            Start-Sleep -Seconds 5
            $pbi = Get-Process PBIDesktop -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like '*Gestão de KPI*' } |
                Select-Object -First 1
            if (-not $pbi -and (Get-Date) -ge $nextWaitLog) {
                Write-Log 'Ainda aguardando o Power BI carregar o relatório...'
                $nextWaitLog = (Get-Date).AddSeconds(30)
            }
        } while (-not $pbi -and (Get-Date) -lt $deadline)
        if ($pbi) {
            Write-Log 'Janela do Power BI pronta; continuando a atualização.'
            Start-Sleep -Seconds 10
        }
    }

    if ($pbi) {
        try { $pbi.PriorityClass = 'BelowNormal' } catch {}
        $shell = New-Object -ComObject WScript.Shell
        if (Set-ForegroundWindow $pbi.MainWindowHandle) {
            Start-Sleep -Seconds 2
            $shell.SendKeys('{ESC}')
            Start-Sleep -Seconds 1
            try {
                Invoke-PowerBISchemaAndDataRefresh $pbi
                Write-Log 'Esquema e dados da tabela Base_Gestão_de_pedidos_ atualizados automaticamente.'
            } catch {
                Write-Log "Atualização direta indisponível; usando atualização da faixa de opções: $($_.Exception.Message)"
                $shell.SendKeys('%hr')
                Start-Sleep -Seconds 90
            }
            Start-Sleep -Seconds 3
            Set-ForegroundWindow $pbi.MainWindowHandle | Out-Null
            $shell.SendKeys('^s')
            Write-Log 'Comando Salvar enviado ao Power BI.'
            Set-Content -LiteralPath $stateFile -Value $candidateId -Encoding UTF8
        } else {
            throw 'A base foi atualizada, mas não foi possível ativar a janela do Power BI.'
        }
    } else {
        throw 'A base foi atualizada, mas o Power BI não ficou pronto após 10 minutos.'
    }
} catch {
    Write-Log "ERRO: $($_.Exception.Message)"
    exit 1
}












