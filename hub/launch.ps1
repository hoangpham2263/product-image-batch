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
    $form = New-Object Windows.Forms.Form -Property @{ Text = ('Tools Hub ' + (Get-InstalledVersion $root)).Trim(); Size = '1120,840'; MinimumSize = '1040,760'; StartPosition = 'CenterScreen'; BackColor = [Drawing.Color]::FromArgb(240, 240, 240); Font = New-Object Drawing.Font('Segoe UI', 10) }
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
    # Cấu hình: the settings every tool shares (hub/setup), left of Cập nhật as in each tool's window.
    . (Join-Path $PSScriptRoot 'setup/setup-dialog.ps1')
    $btnConfig = New-Object Windows.Forms.Button -Property @{ Text = 'Cấu hình'; Size = '100,32'; Anchor = 'Top,Right' }
    Set-FlatButton $btnConfig
    $placeConfig = { $btnConfig.Location = New-Object Drawing.Point(($btnUpdate.Left - 8 - 100), 16) }
    & $placeConfig
    $form.Controls.Add($btnConfig)
    # Whether Cấu hình is done, above the tools: every step but the quota must be OK before the tools work. Checked in
    # the background (setup-check.ps1) when the menu opens and after Cấu hình closes; Cấu hình turns green until done.
    $setupBox = New-Object Windows.Forms.Panel -Property @{ Location = '20,78'; Size = '1064,44'; Anchor = 'Top,Left,Right'; BackColor = [Drawing.Color]::White; BorderStyle = 'FixedSingle' }
    $setupText = New-Object Windows.Forms.Label -Property @{ Location = '12,0'; Size = '900,42'; Anchor = 'Top,Left,Right'; TextAlign = 'MiddleLeft'; AutoEllipsis = $true; Text = '○  Đang kiểm tra cấu hình…'; ForeColor = $script:Ui.Muted }
    $setupFix = New-Object Windows.Forms.Button -Property @{ Text = 'Cấu hình ngay'; Size = '130,30'; Location = '922,6'; Anchor = 'Top,Right'; Visible = $false }
    Set-FlatButton $setupFix -Primary
    $setupBox.Controls.AddRange(@($setupText, $setupFix)); $form.Controls.Add($setupBox)
    $setupOut = Join-Path $logDir "menu-setup-$PID.json"
    $script:setupCheck = $null
    $setupTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 500 }
    $startSetupCheck = {
        if ($script:setupCheck) { return }
        $setupText.Text = '○  Đang kiểm tra cấu hình…'; $setupText.ForeColor = $script:Ui.Muted; $setupFix.Visible = $false
        $script:setupCheck = Start-Process powershell.exe -WindowStyle Hidden -PassThru -RedirectStandardOutput $setupOut -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot 'setup/setup-check.ps1') + '"'), '-AsJson')
        $setupTimer.Start()
    }
    $setupTimer.Add_Tick({
        if (-not $script:setupCheck.HasExited) { return }
        $setupTimer.Stop(); $script:setupCheck.Dispose(); $script:setupCheck = $null
        $names = @{ drive = 'mật khẩu app'; node = 'Node.js'; codex = 'Codex'; login = 'đăng nhập ChatGPT' }
        try {
            $steps = @((Get-Content -LiteralPath $setupOut -Raw -Encoding UTF8 | ConvertFrom-Json).Steps)
            $missing = @($steps | Where-Object { $names.ContainsKey([string]$_.Id) -and $_.State -notin @('ok', 'warn') } | ForEach-Object { $names[[string]$_.Id] })
            if ($missing.Count) {
                $setupText.Text = "✖  Chưa cấu hình xong: còn thiếu $($missing -join ', '). Cấu hình đủ rồi mới dùng được các công cụ."
                $setupText.ForeColor = $script:Ui.Warn; $setupFix.Visible = $true; Set-FlatButton $btnConfig -Primary
            } else {
                $setupText.Text = '✔  Đã cấu hình đủ. Các công cụ sẵn sàng dùng.'
                $setupText.ForeColor = $script:Ui.Ok; Set-FlatButton $btnConfig
            }
        } catch { $setupText.Text = '!  Chưa kiểm tra được cấu hình. Bấm Cấu hình để xem.'; $setupText.ForeColor = $script:Ui.Warn }
    })
    $btnConfig.Add_Click({ Show-HubSetup $form $root; & $startSetupCheck })
    $setupFix.Add_Click({ $btnConfig.PerformClick() })
    $form.Add_Shown({
        & $startSetupCheck
        try {
            $next = Get-AppUpdate $root
            if ($next) { $btnUpdate.Text = "Cập nhật $next"; $btnUpdate.Width = 150; $btnUpdate.Left = $form.ClientSize.Width - 24 - 150; Set-FlatButton $btnUpdate -Primary; & $placeConfig }
        } catch { }
    })
    # Tools in a 4-column grid, as on macOS (hub/picker.mjs): icon and name, the platforms it works with ("platforms" in
    # tool.json), then what it does ("features"). The whole card opens the tool.
    $cols = 4; $rows = [Math]::Ceiling($tools.Count / $cols)
    $grid = New-Object Windows.Forms.TableLayoutPanel -Property @{ Location = '20,134'; Size = (New-Object Drawing.Size(1076, ($rows * 212))); Anchor = 'Top,Left,Right'; ColumnCount = $cols; RowCount = $rows }
    for ($i = 0; $i -lt $cols; $i++) { [void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 25))) }
    for ($i = 0; $i -lt $rows; $i++) { [void]$grid.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 212))) }
    $script:cardPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(172, 172, 172))
    $hover = [Drawing.Color]::FromArgb(230, 238, 248)
    $muted = [Drawing.Color]::FromArgb(96, 96, 96)
    # Any control in a card finds its card, the panel whose Tag is the tool.
    $cardOf = { param($c) while ($c -and -not ($c -is [Windows.Forms.Panel] -and $c.Name -eq 'toolCard')) { $c = $c.Parent }; $c }
    $openCard = { param($s) $card = & $cardOf $s; if ($card.Tag.web) { Start-Process (Join-Path $card.Tag.Root $card.Tag.web) } else { $form.Tag = $card.Tag; $form.Close() } }
    $enterCard = { param($s) (& $cardOf $s).BackColor = $hover }
    $leaveCard = { param($s) $card = & $cardOf $s; if (-not $card.ClientRectangle.Contains($card.PointToClient([Windows.Forms.Cursor]::Position))) { $card.BackColor = [Drawing.Color]::White } }
    foreach ($item in $tools) {
        $card = New-Object Windows.Forms.Panel -Property @{ Name = 'toolCard'; Tag = $item; Dock = 'Fill'; Margin = '0,0,12,12'; BackColor = [Drawing.Color]::White; Cursor = 'Hand' }
        $card.Add_Paint({ param($s, $e) $e.Graphics.DrawRectangle($script:cardPen, 0, 0, $s.Width - 1, $s.Height - 1) })
        $png = Join-Path $item.Root ([IO.Path]::ChangeExtension([string]$item.icon, '.png'))
        $icon = New-Object Windows.Forms.PictureBox -Property @{ Location = '14,14'; Size = '40,40'; SizeMode = 'Zoom'; BackColor = [Drawing.Color]::Transparent }
        if (Test-Path -LiteralPath $png) { $icon.Image = New-Object Drawing.Bitmap($png) }
        $name = New-Object Windows.Forms.Label -Property @{ Text = $item.name; Location = '64,14'; AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 11); BackColor = [Drawing.Color]::Transparent }
        $name.Top = 34 - [int]($name.PreferredHeight / 2)
        $card.Controls.AddRange(@($icon, $name))
        if ($item.status) {
            $tag = New-Object Windows.Forms.Label -Property @{ Text = $item.status; AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 8); ForeColor = [Drawing.Color]::FromArgb(176, 96, 0); BorderStyle = 'FixedSingle'; Padding = '2,0,2,0' }
            $tag.Location = New-Object Drawing.Point(($name.Left + $name.PreferredWidth + 4), ($name.Top + 3))
            $card.Controls.Add($tag)
        }
        # Platforms: grey chips, each with its colour dot drawn at the left.
        $chips = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Location = '14,66'; AutoSize = $true; MaximumSize = '220,0'; BackColor = [Drawing.Color]::Transparent; Margin = '0,0,0,0' }
        foreach ($p in @($item.platforms)) {
            if (-not $p) { continue }
            $chip = New-Object Windows.Forms.Label -Property @{ Text = $p.name; AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 8.5); BackColor = [Drawing.Color]::FromArgb(240, 240, 240); BorderStyle = 'FixedSingle'; Padding = '14,2,4,2'; Margin = '0,0,4,4'; Tag = [Drawing.ColorTranslator]::FromHtml([string]$p.color) }
            $chip.Add_Paint({ param($s, $e) $e.Graphics.SmoothingMode = 'AntiAlias'; $b = New-Object Drawing.SolidBrush($s.Tag); $e.Graphics.FillEllipse($b, 5, [int](($s.Height - 8) / 2) - 1, 8, 8); $b.Dispose() })
            $chips.Controls.Add($chip)
        }
        $features = New-Object Windows.Forms.Label -Property @{ Text = ((@($item.features) | Where-Object { $_ } | ForEach-Object { "•  $_" }) -join "`r`n"); Location = '14,100'; AutoSize = $true; MaximumSize = '230,0'; ForeColor = $muted; Font = New-Object Drawing.Font('Segoe UI', 9); BackColor = [Drawing.Color]::Transparent }
        $card.Controls.AddRange(@($chips, $features))
        # Chips wrap to the card's width; the lines follow them.
        $card.Add_Resize({ param($s) $c = $s.Controls | Where-Object { $_ -is [Windows.Forms.FlowLayoutPanel] }; $f = $s.Controls | Where-Object { $_ -is [Windows.Forms.Label] -and $_.Top -ge 66 }
            $c.MaximumSize = New-Object Drawing.Size(($s.Width - 28), 0); $f.MaximumSize = New-Object Drawing.Size(($s.Width - 28), 0); $f.Top = $c.Bottom + 6 })
        foreach ($c in @($card) + @($card.Controls) + @($chips.Controls)) { $c.Add_Click($openCard); $c.Add_MouseEnter($enterCard); $c.Add_MouseLeave($leaveCard); $c.Cursor = 'Hand' }
        [void]$grid.Controls.Add($card)
    }
    $form.Controls.Add($grid)
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
