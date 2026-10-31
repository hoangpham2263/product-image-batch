# Opens Tools Hub: tidies an install updated from before Tools Hub, then shows the tools (apps/*/tool.json, each with
# its icon) and opens the one picked. On Windows every tool is a WinForms window ("windows" in tool.json), opened in
# its own process while the menu waits hidden; on macOS a tool is a web page ("web") or a Node server ("mac"):
# start-app.command gets the Node entry to start printed, hub/picker.mjs when there is more than one tool.
# -Migrate only tidies the layout.
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
    [Windows.Forms.Application]::EnableVisualStyles()
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
    $updateOut = Join-Path $logDir "menu-update-$PID.txt"
    $script:menuUpdateCheck = $null
    $menuUpdateTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 500 }
    $menuUpdateTimer.Add_Tick({
        if (-not $script:menuUpdateCheck -or -not $script:menuUpdateCheck.HasExited) { return }
        $menuUpdateTimer.Stop()
        try {
            $script:menuUpdateCheck.WaitForExit()
            $next = (Get-Content -LiteralPath $updateOut -Raw -Encoding UTF8 -ErrorAction SilentlyContinue).Trim()
            if ($script:menuUpdateCheck.ExitCode -eq 0 -and $next -match '^v?\d+\.\d+\.\d+$') {
                $btnUpdate.Text = "Cập nhật $next"; $btnUpdate.Width = 150; $btnUpdate.Left = $form.ClientSize.Width - 24 - 150; Set-FlatButton $btnUpdate -Primary; & $placeConfig
            }
        } catch { } finally { $script:menuUpdateCheck.Dispose(); $script:menuUpdateCheck = $null }
    })
    $form.Add_Shown({
        # No button starts focused: Windows would draw it with a thick black border.
        $form.ActiveControl = $null
        & $startSetupCheck
        try {
            $script:menuUpdateCheck = Start-Process powershell.exe -WindowStyle Hidden -PassThru -RedirectStandardOutput $updateOut -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot 'update.ps1') + '"'), '-Root', ('"' + $root + '"'), '-Check')
            $menuUpdateTimer.Start()
        } catch { }
    })
    # Tools in a 3-column grid, as on macOS (hub/picker.mjs): icon, name and the platforms it works with ("platforms" in
    # tool.json), a line, then what it does ("features"). No bold text; the whole card opens the tool.
    $cols = 3; $rows = [Math]::Ceiling($tools.Count / $cols)
    $grid = New-Object Windows.Forms.TableLayoutPanel -Property @{ Location = '20,134'; Size = (New-Object Drawing.Size(1076, ($rows * 202))); Anchor = 'Top,Left,Right'; ColumnCount = $cols; RowCount = $rows }
    for ($i = 0; $i -lt $cols; $i++) { [void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', (100 / $cols)))) }
    for ($i = 0; $i -lt $rows; $i++) { [void]$grid.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 202))) }
    $script:cardPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(172, 172, 172))
    $script:cardHoverPen = New-Object Drawing.Pen($script:Ui.Accent)
    $script:rulePen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(227, 227, 227))
    $script:smallFont = New-Object Drawing.Font('Segoe UI', 8.5)
    $script:featureFont = New-Object Drawing.Font('Segoe UI', 9.75)
    $muted = [Drawing.Color]::FromArgb(96, 96, 96)
    # Any control in a card finds its card, the panel whose Tag is the tool.
    $cardOf = { param($c) while ($c -and -not ($c -is [Windows.Forms.Panel] -and $c.Name -eq 'toolCard')) { $c = $c.Parent }; $c }
    $script:toolProcess = $null
    $script:toolWindowTitle = ''
    $toolTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 200 }
    $toolTimer.Add_Tick({
        if (-not $script:toolProcess) { return }
        $script:toolProcess.Refresh()
        if (-not $script:toolProcess.HasExited) {
            # Keep the menu visible until the real tool has a window, including startup failures.
            if ($script:toolProcess.MainWindowHandle -ne 0 -and $script:toolProcess.MainWindowTitle.StartsWith($script:toolWindowTitle)) { $form.Hide() }
            return
        }
        $toolTimer.Stop(); $script:toolProcess.WaitForExit(); $toolExitCode = $script:toolProcess.ExitCode
        $script:toolProcess.Dispose(); $script:toolProcess = $null
        # 3: the tool installed an update (hub/native-window.ps1); this menu's code is old, so a new one opens.
        if ($toolExitCode -eq 3) {
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot 'launch.ps1') + '"'))
            $form.Close(); return
        }
        $form.Show(); $form.Activate()
        if ($toolExitCode -ne 0) {
            $setupText.Text = 'Không mở được công cụ. Chi tiết đã lưu trong workspace/logs/tool-startup-error.log.'
            $setupText.ForeColor = $script:Ui.Error
        }
    })
    $openCard = {
        param($s)
        $card = & $cardOf $s
        if ($script:toolProcess) { return }
        $previousMenu = $env:TOOLS_HUB_MENU
        try {
            $env:TOOLS_HUB_MENU = 'return'
            $script:toolWindowTitle = [string]$card.Tag.name
            if (-not $card.Tag.windows) { throw 'Công cụ chưa có giao diện Windows native.' }
            $script:toolProcess = Start-Process powershell.exe -PassThru -RedirectStandardError (Join-Path $logDir 'tool-startup-error.log') -ArgumentList @('-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $card.Tag.Root $card.Tag.windows) + '"'))
            [void]$script:toolProcess.Handle
            $toolTimer.Start()
        } catch {
            [void][Windows.Forms.MessageBox]::Show($form, "Không mở được công cụ: $($_.Exception.Message)", 'Tools Hub')
        } finally { $env:TOOLS_HUB_MENU = $previousMenu }
    }
    foreach ($item in $tools) {
        $card = New-Object ToolsHub.ToolCard -Property @{ Name = 'toolCard'; Tag = $item; Dock = 'Fill'; Margin = '0,0,12,12'; BackColor = [Drawing.Color]::White; Cursor = 'Hand' }
        # Border (green on hover), the line under the head, and the platforms: a colour dot and the name each.
        $card.Add_Paint({ param($s, $e)
            $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
            $g.DrawRectangle($(if ($s.Hovered) { $script:cardHoverPen } else { $script:cardPen }), 0, 0, $s.Width - 1, $s.Height - 1)
            # Hover invalidates only the border; do not measure and redraw all the card text for it.
            if (-not $e.ClipRectangle.IntersectsWith((New-Object Drawing.Rectangle(2, 2, ($s.Width - 4), ($s.Height - 4))))) { return }
            $g.DrawLine($script:rulePen, 16, 80, $s.Width - 17, 80)
            $x = 76
            foreach ($p in @($s.Tag.platforms)) {
                if (-not $p) { continue }
                $b = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml([string]$p.color)); $g.FillEllipse($b, $x, 50, 7, 7); $b.Dispose()
                [Windows.Forms.TextRenderer]::DrawText($g, [string]$p.name, $script:smallFont, (New-Object Drawing.Point(($x + 11), 45)), [Drawing.Color]::FromArgb(96, 96, 96))
                $x += 11 + [Windows.Forms.TextRenderer]::MeasureText([string]$p.name, $script:smallFont).Width + 8
            }
            $y = 92
            foreach ($f in @($s.Tag.features)) {
                if (-not $f) { continue }
                [Windows.Forms.TextRenderer]::DrawText($g, '✓', $script:featureFont, (New-Object Drawing.Point(16, $y)), $script:Ui.Accent)
                [Windows.Forms.TextRenderer]::DrawText($g, [string]$f, $script:featureFont, (New-Object Drawing.Rectangle(36, $y, ($s.Width - 52), 22)), [Drawing.Color]::FromArgb(30, 30, 30), [Windows.Forms.TextFormatFlags]'EndEllipsis')
                $y += 23
            }
        })
        $png = Join-Path $item.Root ([IO.Path]::ChangeExtension([string]$item.icon, '.png'))
        $icon = New-Object Windows.Forms.PictureBox -Property @{ Location = '16,16'; Size = '48,48'; SizeMode = 'Zoom'; BackColor = [Drawing.Color]::Transparent }
        if (Test-Path -LiteralPath $png) { $icon.Image = New-Object Drawing.Bitmap($png) }
        $name = New-Object Windows.Forms.Label -Property @{ Text = $item.name; Location = '74,18'; AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 11); BackColor = [Drawing.Color]::Transparent }
        $card.Controls.AddRange(@($icon, $name))
        $card.Add_Resize({ param($s) $s.Invalidate() })
        foreach ($c in @($card) + @($card.Controls)) { $c.Add_Click($openCard); $c.Cursor = 'Hand' }
        [void]$grid.Controls.Add($card)
    }
    $form.Controls.Add($grid)
    $footer = New-Object Windows.Forms.Label -Property @{ Text = "© $((Get-Date).Year) Tools Hub"; Dock = 'Bottom'; Height = 36; TextAlign = 'MiddleCenter'; ForeColor = [Drawing.Color]::FromArgb(96, 96, 96); Font = New-Object Drawing.Font('Segoe UI', 9) }
    $form.Controls.Add($footer)
    # A modeless application loop keeps running while the menu is hidden behind a tool.
    try { [Windows.Forms.Application]::Run($form) }
    finally {
        $setupTimer.Stop(); $setupTimer.Dispose(); $toolTimer.Stop(); $toolTimer.Dispose()
        $menuUpdateTimer.Stop(); $menuUpdateTimer.Dispose()
        if ($script:menuUpdateCheck) { $script:menuUpdateCheck.Dispose(); $script:menuUpdateCheck = $null }
        if ($script:setupCheck) { $script:setupCheck.Dispose(); $script:setupCheck = $null }
        if ($script:toolProcess) { $script:toolProcess.Dispose(); $script:toolProcess = $null }
        $form.Dispose()
        $script:cardPen.Dispose(); $script:cardHoverPen.Dispose(); $script:rulePen.Dispose()
        $script:smallFont.Dispose(); $script:featureFont.Dispose()
    }
    if (-not $form.Tag) { return }
    $tool = $form.Tag
}
if (-not $tool.windows) { throw 'Công cụ chưa có giao diện Windows native.' }
# The tool shows "← Menu" back here when there is a menu to go back to.
if ($tools.Count -gt 1) { $env:TOOLS_HUB_MENU = '1' }
& (Join-Path $tool.Root $tool.windows)
