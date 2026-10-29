# Kiểm tra cấu hình: every step the app needs, in order (app password, installed, signed in, usable). A step that is
# not done has its own button that runs the fix; the window returns that step's action, or '' when closed.
function Show-SetupDialog([Windows.Forms.Form]$Owner, [string]$SrcDir, [string]$LogDir) {
    $ui = $script:Ui
    $dialog = New-Object Windows.Forms.Form -Property @{ Text = 'Kiểm tra cấu hình'; ClientSize = '520,430'; StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'; MinimizeBox = $false; MaximizeBox = $false; ShowInTaskbar = $false; Font = (New-Object Drawing.Font('Segoe UI', 10)) }
    $titles = @('Mật khẩu app', 'Node.js', 'Codex', 'Đăng nhập ChatGPT', 'Hạn mức sử dụng')
    $rows = @()
    for ($i = 0; $i -lt $titles.Count; $i++) {
        $y = 16 + $i * 58
        $icon = New-Object Windows.Forms.Label -Property @{ Location = (New-Object Drawing.Point(20, $y)); Size = '26,24'; Font = (New-Object Drawing.Font('Segoe UI Symbol', 12)) }
        $name = New-Object Windows.Forms.Label -Property @{ Text = $titles[$i]; Location = (New-Object Drawing.Point(52, $y)); Size = '330,22' }
        $detail = New-Object Windows.Forms.Label -Property @{ Location = (New-Object Drawing.Point(52, ($y + 22))); Size = '330,32'; ForeColor = $ui.Muted; AutoEllipsis = $true }
        $fix = New-Object Windows.Forms.Button -Property @{ Location = (New-Object Drawing.Point(390, ($y + 6))); Size = '110,32'; Visible = $false }
        Set-FlatButton $fix -Primary
        $dialog.Controls.AddRange(@($icon, $name, $detail, $fix))
        $rows += [pscustomobject]@{ Icon = $icon; Detail = $detail; Fix = $fix }
    }
    # Model AI: the model and reasoning level Codex uses (Get-AiSettings); lighter ones use fewer tokens.
    $aiTitle = New-Object Windows.Forms.Label -Property @{ Text = 'Model AI · model nhẹ, mức thấp tốn ít token hơn'; Location = '52,306'; Size = '448,22' }
    $aiModel = New-Object Windows.Forms.ComboBox -Property @{ Name = 'AiModel'; Location = '52,332'; Size = '250,28'; DropDownStyle = 'DropDownList' }
    $aiEffort = New-Object Windows.Forms.ComboBox -Property @{ Name = 'AiEffort'; Location = '312,332'; Size = '188,28'; DropDownStyle = 'DropDownList' }
    $dialog.Controls.AddRange(@($aiTitle, $aiModel, $aiEffort)); Set-ComboChevron $aiModel; Set-ComboChevron $aiEffort
    $again = New-Object Windows.Forms.Button -Property @{ Text = 'Kiểm tra lại'; Location = '290,380'; Size = '110,34' }
    $close = New-Object Windows.Forms.Button -Property @{ Text = 'Đóng'; Location = '410,380'; Size = '90,34'; DialogResult = 'Cancel' }
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
                if ($steps[$i].Action) { $row.Fix.Tag = $steps[$i].Action; $row.Fix.Text = $(if ($steps[$i].Action -eq 'install') { 'Cài' } elseif ($steps[$i].Action -eq 'drive' -and $steps[$i].State -eq 'ok') { 'Đổi' } else { 'Đăng nhập' }); $row.Fix.Visible = $true; Set-FlatButton $row.Fix -Primary:($steps[$i].State -ne 'ok') }
            }
        } catch { $rows[0].Detail.Text = 'Chưa kiểm tra được. Bấm Kiểm tra lại.' }
        finally { $dialog.Cursor = 'Default'; $again.Enabled = $true }
    }.GetNewClosure()
    $ai = @{ Models = @(); Efforts = @(); Filling = $false }
    $effortNames = @{ low = 'Thấp · ít token nhất'; medium = 'Vừa'; high = 'Cao'; xhigh = 'Rất cao'; max = 'Tối đa'; ultra = 'Siêu cao' }
    $fillEfforts = {
        param([string]$Selected)
        $model = if ($aiModel.SelectedIndex -gt 0) { $ai.Models[$aiModel.SelectedIndex - 1] } else { $null }
        $ai.Efforts = @('') + @(if ($model) { $model.efforts } else { @('low', 'medium', 'high') })
        $aiEffort.Items.Clear()
        foreach ($e in $ai.Efforts) { [void]$aiEffort.Items.Add($(if ($e) { $effortNames[$e] + $(if ($model -and $e -eq $model.default_effort) { ' (mặc định)' }) } else { 'Mức suy nghĩ mặc định' })) }
        $aiEffort.SelectedIndex = [Math]::Max(0, [array]::IndexOf([string[]]$ai.Efforts, $Selected))
    }.GetNewClosure()
    $saveAi = {
        if ($ai.Filling) { return }
        $ai.Filling = $true
        try { & $fillEfforts $(if ($aiEffort.SelectedIndex -gt 0) { $ai.Efforts[$aiEffort.SelectedIndex] } else { '' }) } finally { $ai.Filling = $false }
        Set-AiSettings (Split-Path $SrcDir -Parent) $(if ($aiModel.SelectedIndex -gt 0) { $ai.Models[$aiModel.SelectedIndex - 1].slug } else { '' }) $ai.Efforts[$aiEffort.SelectedIndex]
    }.GetNewClosure()
    $loadAi = {
        $ai.Filling = $true
        try {
            $saved = Get-AiSettings (Split-Path $SrcDir -Parent)
            $ai.Models = @(Get-AiModels)
            if ($saved.model -and -not @($ai.Models | Where-Object slug -eq $saved.model).Count) { $ai.Models = @([pscustomobject]@{ slug = $saved.model; name = $saved.model; efforts = @('low', 'medium', 'high'); default_effort = '' }) + $ai.Models }
            $aiModel.Items.Clear(); [void]$aiModel.Items.Add('Model mặc định của Codex')
            foreach ($m in $ai.Models) { [void]$aiModel.Items.Add($m.name) }
            $aiModel.SelectedIndex = 1 + [array]::IndexOf([string[]]@($ai.Models | ForEach-Object slug), $saved.model)
            & $fillEfforts $saved.effort
        } finally { $ai.Filling = $false }
    }.GetNewClosure()
    $aiModel.Add_SelectedIndexChanged($saveAi); $aiEffort.Add_SelectedIndexChanged($saveAi)
    $again.Add_Click($check)
    $dialog.Add_Shown({ & $loadAi; & $check }.GetNewClosure())
    try { if ($dialog.ShowDialog($Owner) -eq 'OK') { return $state.Action } else { return '' } } finally { $dialog.Dispose() }
}
