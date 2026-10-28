# Kiểm tra cấu hình: every step the app needs, in order (app password, installed, signed in, usable). A step that is
# not done has its own button that runs the fix; the window returns that step's action, or '' when closed.
function Show-SetupDialog([Windows.Forms.Form]$Owner, [string]$SrcDir, [string]$LogDir) {
    $ui = $script:Ui
    $dialog = New-Object Windows.Forms.Form -Property @{ Text = 'Kiểm tra cấu hình'; ClientSize = '520,372'; StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'; MinimizeBox = $false; MaximizeBox = $false; ShowInTaskbar = $false; Font = (New-Object Drawing.Font('Segoe UI', 10)) }
    $titles = @('Mật khẩu app', 'Node.js', 'Codex', 'Đăng nhập ChatGPT', 'Hạn mức sử dụng')
    $rows = @()
    for ($i = 0; $i -lt $titles.Count; $i++) {
        $y = 16 + $i * 58
        $icon = New-Object Windows.Forms.Label -Property @{ Location = (New-Object Drawing.Point(20, $y)); Size = '26,24'; Font = (New-Object Drawing.Font('Segoe UI Symbol', 12)) }
        $name = New-Object Windows.Forms.Label -Property @{ Text = $titles[$i]; Location = (New-Object Drawing.Point(52, $y)); Size = '448,22' }
        $detail = New-Object Windows.Forms.Label -Property @{ Location = (New-Object Drawing.Point(52, ($y + 22))); Size = '330,32'; ForeColor = $ui.Muted; AutoEllipsis = $true }
        $fix = New-Object Windows.Forms.Button -Property @{ Location = (New-Object Drawing.Point(390, ($y + 6))); Size = '110,32'; Visible = $false }
        Set-FlatButton $fix -Primary
        $dialog.Controls.AddRange(@($icon, $name, $detail, $fix))
        $rows += [pscustomobject]@{ Icon = $icon; Detail = $detail; Fix = $fix }
    }
    $again = New-Object Windows.Forms.Button -Property @{ Text = 'Kiểm tra lại'; Location = '290,322'; Size = '110,34' }
    $close = New-Object Windows.Forms.Button -Property @{ Text = 'Đóng'; Location = '410,322'; Size = '90,34'; DialogResult = 'Cancel' }
    Set-FlatButton $again; Set-FlatButton $close
    $dialog.Controls.AddRange(@($again, $close)); $dialog.CancelButton = $close
    $state = @{ Action = '' }
    foreach ($row in $rows) { $row.Fix.Add_Click({ $state.Action = $this.Tag; $dialog.DialogResult = 'OK'; $dialog.Close() }.GetNewClosure()) }
    $check = {
        $dialog.Cursor = 'WaitCursor'; $again.Enabled = $false; $state.Action = ''
        foreach ($row in $rows) { $row.Icon.Text = '○'; $row.Icon.ForeColor = $ui.Muted; $row.Detail.Text = 'Đang kiểm tra…'; $row.Fix.Visible = $false }
        $dialog.Refresh()
        $out = Join-Path $LogDir "setup-check-$PID.json"; $err = Join-Path $LogDir "setup-check-$PID.err.log"
        try {
            Start-Process powershell.exe -WindowStyle Hidden -Wait -RedirectStandardOutput $out -RedirectStandardError $err -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $SrcDir 'setup-check.ps1') + '"'), '-AsJson')
            $steps = @((Get-Content -LiteralPath $out -Raw -Encoding UTF8 | ConvertFrom-Json).Steps)
            for ($i = 0; $i -lt [Math]::Min($rows.Count, $steps.Count); $i++) {
                $row = $rows[$i]
                switch ($steps[$i].State) {
                    'ok' { $row.Icon.Text = '✔'; $row.Icon.ForeColor = $ui.Ok }
                    'fail' { $row.Icon.Text = '✖'; $row.Icon.ForeColor = $ui.Error }
                    'warn' { $row.Icon.Text = '!'; $row.Icon.ForeColor = $ui.Warn }
                    default { $row.Icon.Text = '○'; $row.Icon.ForeColor = $ui.Muted }
                }
                $row.Detail.Text = [string]$steps[$i].Detail
                if ($steps[$i].Action) { $row.Fix.Tag = $steps[$i].Action; $row.Fix.Text = $(if ($steps[$i].Action -eq 'install') { 'Cài' } elseif ($steps[$i].Action -eq 'drive' -and $steps[$i].State -eq 'ok') { 'Đổi' } else { 'Đăng nhập' }); $row.Fix.Visible = $true }
            }
        } catch { $rows[0].Detail.Text = 'Chưa kiểm tra được. Bấm Kiểm tra lại.' }
        finally { $dialog.Cursor = 'Default'; $again.Enabled = $true }
    }.GetNewClosure()
    $again.Add_Click($check)
    $dialog.Add_Shown($check)
    try { if ($dialog.ShowDialog($Owner) -eq 'OK') { return $state.Action } else { return '' } } finally { $dialog.Dispose() }
}
