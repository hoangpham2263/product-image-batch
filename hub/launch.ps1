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
        & open -na 'Google Chrome' --args "--app=$url" '--window-size=1120,840'; if ($LASTEXITCODE) { & open $url }
        return
    }
    return (Join-Path $tools[0].Root $tools[0].mac)
}

$tool = $tools[0]
if ($tools.Count -gt 1) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $form = New-Object Windows.Forms.Form -Property @{ Text = 'Tools Hub'; Size = '1120,840'; MinimumSize = '1040,760'; StartPosition = 'CenterScreen'; BackColor = [Drawing.Color]::FromArgb(240, 240, 240); Font = New-Object Drawing.Font('Segoe UI', 10) }
    $hubIcon = Join-Path $PSScriptRoot 'assets/icon.png'
    if (Test-Path -LiteralPath $hubIcon) { $form.Icon = [Drawing.Icon]::FromHandle((New-Object Drawing.Bitmap($hubIcon)).GetHicon()) }
    # Same size and 20px sides as Product Review's window; the title row is 64px high like its header.
    $title = New-Object Windows.Forms.Label -Property @{ Text = 'Tools Hub'; Location = '20,19'; AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 13) }
    $form.Controls.Add($title)
    # Cập nhật: top right in every window, as in Product Review; green with the version once a newer one is out.
    . (Join-Path $PSScriptRoot 'winforms.ps1'); . (Join-Path $PSScriptRoot 'update-dialog.ps1')
    $logDir = Join-Path $root 'workspace/logs'; New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $current = Get-InstalledVersion $root
    $btnUpdate = New-Object Windows.Forms.Button -Property @{ Text = 'Cập nhật'; Size = '100,32'; Anchor = 'Top,Right' }
    $btnUpdate.Location = New-Object Drawing.Point(($form.ClientSize.Width - 24 - 100), 16)
    Set-FlatButton $btnUpdate
    $btnUpdate.Add_Click({
        if (Show-UpdateDialog $form $root $logDir $current) {
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot 'launch.ps1') + '"'))
            $form.Close()
        }
    })
    $form.Controls.Add($btnUpdate)
    $form.Add_Shown({
        try {
            $next = Get-AppUpdate $root
            if ($next) { $btnUpdate.Text = "Cập nhật $next"; $btnUpdate.Width = 150; $btnUpdate.Left = $form.ClientSize.Width - 24 - 150; Set-FlatButton $btnUpdate -Primary }
        } catch { }
    })
    $y = 64
    foreach ($item in $tools) {
        $button = New-Object Windows.Forms.Button -Property @{ Left = 20; Top = $y; Width = 1064; Height = 64; Anchor = 'Top,Left,Right'; Tag = $item; FlatStyle = 'Flat'; BackColor = [Drawing.Color]::White; TextAlign = 'MiddleLeft'; ImageAlign = 'MiddleLeft'; TextImageRelation = 'ImageBeforeText'; Padding = '10,0,0,0'; Cursor = 'Hand' }
        $button.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(172, 172, 172); $button.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(230, 238, 248)
        $button.Text = "  $($item.name)"
        $png = Join-Path $item.Root ([IO.Path]::ChangeExtension([string]$item.icon, '.png'))
        if (Test-Path -LiteralPath $png) { $button.Image = New-Object Drawing.Bitmap((New-Object Drawing.Bitmap($png)), 40, 40) }
        # A web tool opens in the browser and the menu stays; a tool with its own window replaces the menu.
        $button.Add_Click({ param($s) if ($s.Tag.web) { Start-Process (Join-Path $s.Tag.Root $s.Tag.web) } else { $form.Tag = $s.Tag; $form.Close() } })
        $form.Controls.Add($button); $y += 72
    }
    $footer = New-Object Windows.Forms.Label -Property @{ Text = "© $((Get-Date).Year) Tools Hub"; Dock = 'Bottom'; Height = 36; TextAlign = 'MiddleCenter'; ForeColor = [Drawing.Color]::FromArgb(96, 96, 96); Font = New-Object Drawing.Font('Segoe UI', 9) }
    $form.Controls.Add($footer)
    [void]$form.ShowDialog()
    if (-not $form.Tag) { return }
    $tool = $form.Tag
}
if ($tool.web) { Start-Process (Join-Path $tool.Root $tool.web); return }
# The tool shows "← Menu" back here when there is a menu to go back to.
if ($tools.Count -gt 1) { $env:TOOLS_HUB_MENU = '1' }
& (Join-Path $tool.Root $tool.windows)
