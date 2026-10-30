# Opens Tools Hub: tidies an install updated from before Tools Hub, then opens the tool chosen (apps/*/tool.json).
# One tool opens straight away. Windows (start-app.cmd) runs the tool's "windows" entry here; macOS (start-app.command)
# gets the tool's "mac" entry printed and starts it with Node. -Migrate only tidies the layout.
param([switch]$Mac, [switch]$Migrate)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'update.ps1') -NoRun
try { Move-LegacyLayout $root } catch { Write-Warning "Không dọn được cấu trúc cũ: $($_.Exception.Message)" }
if ($Migrate) { return }

$tools = @(Get-HubTools $root)
if (-not $tools.Count) { throw 'Không tìm thấy tool nào trong apps/.' }
$tool = $tools[0]
if ($tools.Count -gt 1) {
    if ($Mac) {
        $names = ($tools | ForEach-Object { '"' + ([string]$_.name -replace '"', '') + '"' }) -join ', '
        $picked = (& osascript -e "choose from list {$names} with title `"Tools Hub`" with prompt `"Chọn tool`" default items {$(($names -split ', ')[0])}" 2>$null | Out-String).Trim()
        if (-not $picked -or $picked -eq 'false') { return }
        $tool = @($tools | Where-Object name -eq $picked)[0]
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        $form = New-Object Windows.Forms.Form -Property @{ Text = 'Tools Hub'; Width = 360; Height = 120 + 36 * $tools.Count; StartPosition = 'CenterScreen'; FormBorderStyle = 'FixedDialog'; MaximizeBox = $false; MinimizeBox = $false }
        $y = 16
        foreach ($item in $tools) {
            $button = New-Object Windows.Forms.Button -Property @{ Text = [string]$item.name; Left = 16; Top = $y; Width = 310; Height = 30; Tag = $item }
            $button.Add_Click({ param($s) $form.Tag = $s.Tag; $form.Close() })
            $form.Controls.Add($button); $y += 36
        }
        [void]$form.ShowDialog()
        if (-not $form.Tag) { return }
        $tool = $form.Tag
    }
}
$entry = Join-Path $tool.Root $(if ($Mac) { $tool.mac } else { $tool.windows })
if ($Mac) { return $entry }
& $entry
