# Opens Tools Hub: tidies an install updated from before Tools Hub, then shows the tools (apps/*/tool.json, each with
# its icon) and opens the one picked. A tool runs as "windows" (PowerShell), "mac" (Node server) or "web" (a page
# opened in the browser). Windows (start-app.cmd) shows the picker here; macOS (start-app.command) gets the Node entry
# to start printed: hub/picker.mjs when there is more than one tool. -Migrate only tidies the layout.
param([switch]$Mac, [switch]$Migrate)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'update.ps1') -NoRun
try { Move-LegacyLayout $root } catch { Write-Warning "Không dọn được cấu trúc cũ: $($_.Exception.Message)" }
if ($Migrate) { return }

$tools = @(Get-HubTools $root)
if (-not $tools.Count) { throw 'Không tìm thấy tool nào trong apps/.' }
if ($Mac) {
    if ($tools.Count -gt 1) { return (Join-Path $PSScriptRoot 'picker.mjs') }
    if ($tools[0].web) {
        $url = ([Uri](Join-Path $tools[0].Root $tools[0].web)).AbsoluteUri
        & open -na 'Google Chrome' --args "--app=$url" '--window-size=960,820'; if ($LASTEXITCODE) { & open $url }
        return
    }
    return (Join-Path $tools[0].Root $tools[0].mac)
}

$tool = $tools[0]
if ($tools.Count -gt 1) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $form = New-Object Windows.Forms.Form -Property @{ Text = 'Tools Hub'; ClientSize = '420,80'; StartPosition = 'CenterScreen'; FormBorderStyle = 'FixedDialog'; MaximizeBox = $false; MinimizeBox = $false; BackColor = [Drawing.Color]::White; Font = New-Object Drawing.Font('Segoe UI', 10) }
    $hubIcon = Join-Path $PSScriptRoot 'assets/icon.png'
    if (Test-Path -LiteralPath $hubIcon) { $form.Icon = [Drawing.Icon]::FromHandle((New-Object Drawing.Bitmap($hubIcon)).GetHicon()) }
    $y = 16
    foreach ($item in $tools) {
        $button = New-Object Windows.Forms.Button -Property @{ Left = 16; Top = $y; Width = 388; Height = 64; Tag = $item; FlatStyle = 'Flat'; TextAlign = 'MiddleLeft'; ImageAlign = 'MiddleLeft'; TextImageRelation = 'ImageBeforeText'; Padding = '10,0,0,0'; Cursor = 'Hand' }
        $button.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(226, 232, 240)
        $button.Text = "  $($item.name)`r`n  $($item.description)"
        $png = Join-Path $item.Root ([IO.Path]::ChangeExtension([string]$item.icon, '.png'))
        if (Test-Path -LiteralPath $png) { $button.Image = New-Object Drawing.Bitmap((New-Object Drawing.Bitmap($png)), 40, 40) }
        $button.Add_Click({ param($s) $form.Tag = $s.Tag; $form.Close() })
        $form.Controls.Add($button); $y += 72
    }
    $form.ClientSize = "420,$($y + 8)"
    [void]$form.ShowDialog()
    if (-not $form.Tag) { return }
    $tool = $form.Tag
}
if ($tool.web) { Start-Process (Join-Path $tool.Root $tool.web); return }
& (Join-Path $tool.Root $tool.windows)
