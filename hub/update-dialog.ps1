# Cập nhật (Windows): looks for a newer Tools Hub release and installs it with a running progress bar. Shared by the
# menu (hub/launch.ps1) and every tool's window. Returns $true when the new files are in place, so the window can
# reopen itself on them. Needs hub/winforms.ps1.
function Show-UpdateDialog([Windows.Forms.Form]$Owner, [string]$HubRoot, [string]$LogDir, [string]$Current) {
    $ui = $script:Ui
    $dialog = New-Object Windows.Forms.Form -Property @{ Text = 'Cập nhật'; ClientSize = '440,168'; StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'; MinimizeBox = $false; MaximizeBox = $false; ShowInTaskbar = $false; Font = (New-Object Drawing.Font('Segoe UI', 10)) }
    $status = New-Object Windows.Forms.Label -Property @{ Location = '20,20'; Size = '400,44' }
    $bar = New-Object Windows.Forms.ProgressBar -Property @{ Location = '20,72'; Size = '400,10'; Style = 'Marquee'; MarqueeAnimationSpeed = 30 }
    $go = New-Object Windows.Forms.Button -Property @{ Text = 'Cập nhật'; Location = '220,112'; Size = '100,32'; Visible = $false }
    $close = New-Object Windows.Forms.Button -Property @{ Text = 'Đóng'; Location = '330,112'; Size = '90,32'; DialogResult = 'Cancel' }
    Set-FlatButton $go -Primary; Set-FlatButton $close
    $dialog.Controls.AddRange(@($status, $bar, $go, $close)); $dialog.CancelButton = $close
    $state = @{ Proc = $null; Step = ''; Next = ''; Done = $false }
    $out = Join-Path $LogDir "update-$PID.out.log"; $err = Join-Path $LogDir "update-$PID.err.log"
    $timer = New-Object Windows.Forms.Timer -Property @{ Interval = 300 }
    # The updater runs in its own process so the bar keeps moving while it downloads.
    $start = {
        param($Step, [string[]]$Extra)
        $state.Step = $Step; $bar.Visible = $true; $go.Visible = $false; $close.Enabled = $Step -ne 'apply'
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $HubRoot 'hub\update.ps1') + '"'), '-Root', ('"' + $HubRoot + '"')) + $Extra
        $state.Proc = Start-Process powershell.exe -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -ArgumentList $arguments
        [void]$state.Proc.Handle
        $timer.Start()
    }.GetNewClosure()
    $timer.Add_Tick({
        if (-not $state.Proc.HasExited) { return }
        $timer.Stop(); $state.Proc.WaitForExit(); $code = $state.Proc.ExitCode; $state.Proc.Dispose(); $state.Proc = $null
        $bar.Visible = $false; $close.Enabled = $true
        $text = try { (Get-Content -LiteralPath $out -Raw -ErrorAction Stop).Trim() } catch { '' }
        if ($state.Step -eq 'check') {
            if ($code -ne 0) { $status.Text = 'Không kiểm tra được bản mới. Kiểm tra mạng rồi thử lại.'; return }
            if (-not $text) { $status.Text = "Đang dùng bản mới nhất ($Current)."; return }
            $state.Next = $text
            $status.Text = "Có phiên bản mới $text (đang dùng $Current)."
            $go.Visible = $true; [void]$go.Focus()
        } elseif ($code -ne 0) {
            $status.Text = 'Chưa cập nhật được. Kiểm tra mạng rồi thử lại.'; $go.Text = 'Thử lại'; $go.Visible = $true
        } else {
            $status.Text = 'Đã cập nhật. Đang mở lại app…'; $dialog.Refresh(); $state.Done = $true
            $dialog.DialogResult = 'OK'; $dialog.Close()
        }
    }.GetNewClosure())
    $go.Add_Click({ $status.Text = "Đang tải và cài phiên bản $($state.Next)…"; & $start 'apply' @('-Apply') }.GetNewClosure())
    $dialog.Add_Shown({ $status.Text = 'Đang kiểm tra bản mới…'; & $start 'check' @('-Check') }.GetNewClosure())
    # Closing in the middle of an install would leave half-copied files.
    $dialog.Add_FormClosing({ if ($state.Proc -and $state.Step -eq 'apply') { $_.Cancel = $true } }.GetNewClosure())
    try { [void]$dialog.ShowDialog($Owner); return $state.Done }
    finally { $timer.Dispose(); $dialog.Dispose(); Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue }
}
