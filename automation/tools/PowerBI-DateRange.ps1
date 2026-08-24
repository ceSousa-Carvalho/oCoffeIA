Add-Type -AssemblyName UIAutomationClient

if (-not ([System.Management.Automation.PSTypeName]'PowerBIInputHelper').Type) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PowerBIInputHelper {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
}
'@
}

function Close-PowerBIOverlays {
    param([Parameter(Mandatory = $true)][IntPtr]$WindowHandle, [Parameter(Mandatory = $true)]$Shell)
    $rect = New-Object PowerBIInputHelper+RECT
    if ([PowerBIInputHelper]::GetWindowRect($WindowHandle, [ref]$rect)) {
        $x = $rect.Left + [int](($rect.Right - $rect.Left) * 0.035)
        $y = $rect.Top + [int](($rect.Bottom - $rect.Top) * 0.22)
        [void][PowerBIInputHelper]::SetCursorPos($x, $y)
        1..2 | ForEach-Object {
            [PowerBIInputHelper]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
            [PowerBIInputHelper]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 450
        }
    }
    1..2 | ForEach-Object { $Shell.SendKeys('{ESC}'); Start-Sleep -Milliseconds 250 }
    Start-Sleep -Seconds 1
}

function Select-PowerBIReportPage {
    param(
        [Parameter(Mandatory = $true)][IntPtr]$WindowHandle,
        [Parameter(Mandatory = $true)][string]$PageName
    )
    $root = [Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
    $condition = New-Object Windows.Automation.PropertyCondition(
        [Windows.Automation.AutomationElement]::ControlTypeProperty,
        [Windows.Automation.ControlType]::TabItem
    )
    $tabs = $root.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
    $normalizedTarget = (($PageName -replace '^Hidden\s*', '') -replace '\s+', '').ToUpperInvariant()
    for ($index = 0; $index -lt $tabs.Count; $index++) {
        $tab = $tabs.Item($index)
        $normalizedName = (([string]$tab.Current.Name -replace '^Hidden\s*', '') -replace '\s+', '').ToUpperInvariant()
        if ($normalizedName -ne $normalizedTarget) { continue }
        $pattern = $null
        if (-not $tab.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
            throw "A página '$PageName' foi encontrada, mas não pôde ser selecionada."
        }
        ([Windows.Automation.SelectionItemPattern]$pattern).Select()
        Start-Sleep -Seconds 3
        return
    }
    throw "A página '$PageName' não foi encontrada no Power BI."
}

function Get-PowerBIDateFields {
    param([Parameter(Mandatory = $true)][IntPtr]$WindowHandle)

    $root = [Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
    $condition = New-Object Windows.Automation.PropertyCondition(
        [Windows.Automation.AutomationElement]::ControlTypeProperty,
        [Windows.Automation.ControlType]::Edit
    )
    $edits = $root.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
    $start = $null
    $end = $null
    $dateCandidates = New-Object System.Collections.ArrayList

    for ($index = 0; $index -lt $edits.Count; $index++) {
        $edit = $edits.Item($index)
        $name = [string]$edit.Current.Name
        $pattern = $null
        if (-not $edit.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) { continue }
        $value = ([Windows.Automation.ValuePattern]$pattern).Current.Value

        if ($name -match '^(Start date|Data inicial|Data in[ií]cio)') { $start = $edit; continue }
        if ($name -match '^(End date|Data final)') { $end = $edit; continue }

        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact($value, 'dd/MM/yyyy', [Globalization.CultureInfo]::GetCultureInfo('pt-BR'), [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            [void]$dateCandidates.Add($edit)
        }
    }

    # O nome de acessibilidade muda conforme o idioma do Power BI. Se necessário,
    # usa os dois campos editáveis que contêm datas visíveis na página do relatório.
    if (-not $start -and $dateCandidates.Count -ge 1) { $start = $dateCandidates[0] }
    if (-not $end -and $dateCandidates.Count -ge 2) { $end = $dateCandidates[1] }
    if (-not $start -or -not $end) { throw 'Os dois filtros de data da página do Power BI não foram encontrados.' }

    return [pscustomobject]@{ Start = $start; End = $end }
}

function Get-PowerBIDateFieldValue {
    param([Parameter(Mandatory = $true)]$Element)
    $pattern = $null
    if (-not $Element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
        throw 'O filtro de data encontrado não permite leitura.'
    }
    return ([Windows.Automation.ValuePattern]$pattern).Current.Value
}

function ConvertFrom-PowerBIDateText {
    param([string]$Value)
    $parsed = [datetime]::MinValue
    foreach ($culture in @([Globalization.CultureInfo]::GetCultureInfo('pt-BR'), [Globalization.CultureInfo]::InvariantCulture)) {
        if ([datetime]::TryParse($Value, $culture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $parsed.Date }
    }
    return $null
}

function Set-PowerBIDateField {
    param(
        [Parameter(Mandatory = $true)][IntPtr]$WindowHandle,
        [Parameter(Mandatory = $true)][ValidateSet('Start','End')][string]$Field,
        [Parameter(Mandatory = $true)][string]$DateText,
        [Parameter(Mandatory = $true)]$Shell
    )
    # Reencontra o controle sempre que for alterar. O Power BI recria os elementos
    # de acessibilidade quando um filtro é confirmado.
    $fields = Get-PowerBIDateFields -WindowHandle $WindowHandle
    $element = if ($Field -eq 'Start') { $fields.Start } else { $fields.End }
    $element.SetFocus()
    Start-Sleep -Milliseconds 350
    $Shell.SendKeys('^a')
    $Shell.SendKeys($DateText)
    $Shell.SendKeys('{ENTER}')
    Start-Sleep -Seconds 2
}

function Set-PowerBIDateRangeVerified {
    param(
        [Parameter(Mandatory = $true)][IntPtr]$WindowHandle,
        [Parameter(Mandatory = $true)][datetime]$Date,
        [string]$Context = 'relatório'
    )

    $target = $Date.Date
    $dateText = $target.ToString('dd/MM/yyyy')
    $shell = New-Object -ComObject WScript.Shell

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $fields = Get-PowerBIDateFields -WindowHandle $WindowHandle
        $currentStart = ConvertFrom-PowerBIDateText (Get-PowerBIDateFieldValue $fields.Start)
        $currentEnd = ConvertFrom-PowerBIDateText (Get-PowerBIDateFieldValue $fields.End)

        # Mantém o intervalo válido durante a edição: amplia primeiro a extremidade
        # necessária e depois iguala o outro campo.
        $order = if ($currentEnd -and $target -gt $currentEnd) { @('End','Start') } else { @('Start','End') }
        foreach ($field in $order) {
            Set-PowerBIDateField -WindowHandle $WindowHandle -Field $field -DateText $dateText -Shell $shell
        }

        $verified = Get-PowerBIDateFields -WindowHandle $WindowHandle
        $startValue = Get-PowerBIDateFieldValue $verified.Start
        $endValue = Get-PowerBIDateFieldValue $verified.End
        $verifiedStart = ConvertFrom-PowerBIDateText $startValue
        $verifiedEnd = ConvertFrom-PowerBIDateText $endValue
        if ($verifiedStart -eq $target -and $verifiedEnd -eq $target) {
            # A edição por teclado pode deixar o calendário ou um tooltip aberto.
            # Fecha todas as camadas antes que o relatório seja capturado.
            Close-PowerBIOverlays -WindowHandle $WindowHandle -Shell $shell
            return [pscustomobject]@{ Start = $startValue; End = $endValue; Date = $target; Context = $Context }
        }
        Start-Sleep -Seconds 1
    }

    throw "Datas incorretas no Power BI ($Context). Esperado nos dois filtros: $dateText. Encontrado: início '$startValue' e final '$endValue'. A captura foi cancelada."
}
