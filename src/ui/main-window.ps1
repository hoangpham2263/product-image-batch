# Desktop GUI for run-images.ps1: URL queue, run/stop, live log (Vietnamese), folder shortcuts.
param([switch]$BuildOnly)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'progress.ps1')
. (Join-Path $PSScriptRoot 'drive-login.ps1')
. (Join-Path $PSScriptRoot 'setup-dialog.ps1')
. (Join-Path $PSScriptRoot 'update-dialog.ps1')
. (Join-Path $PSScriptRoot 'app-icon.ps1')

$srcDir = Split-Path $PSScriptRoot -Parent
$root = Split-Path $srcDir -Parent   # project root (base data and local workspace)
. (Join-Path $srcDir 'application/workspace.ps1')
. (Join-Path $srcDir 'application/ai-settings.ps1')
. (Join-Path $srcDir 'infrastructure/platform.ps1')
. (Join-Path $srcDir 'infrastructure/drive-storage.ps1')
$workspace = Initialize-ProjectWorkspace $root
. (Join-Path $srcDir 'infrastructure/source-catalog.ps1')
. (Join-Path $srcDir 'infrastructure/source-sync.ps1')
. (Join-Path $srcDir 'application/agent-lessons.ps1')
. (Join-Path $srcDir 'application/image-feedback.ps1')
. (Join-Path $srcDir 'application/manual-references.ps1')
. (Join-Path $srcDir 'application/batch-import.ps1')
. (Join-Path $srcDir 'infrastructure/csv.ps1')
. (Join-Path $srcDir 'application/batch-review.ps1')
. (Join-Path $srcDir 'application/support-logs.ps1')
. (Join-Path $PSScriptRoot 'image-feedback.ps1')
. (Join-Path $PSScriptRoot 'manual-references.ps1')
. (Join-Path $PSScriptRoot 'batch-review.ps1')
$urlFile = $workspace.Queue
$script:proc = $null
$script:resultFolder = ''
$script:currentIndex = 0
$script:itemStages = @{}
$script:jobRows = @()

function Open-Path([string]$p) { New-Item -ItemType Directory -Force $p | Out-Null; Start-Process explorer.exe $p }
function Count-Urls { @(Get-ProductQueueUrls $queueEditor).Count }

function New-RunArguments([string]$ScriptPath, [int]$PhotosPerImage, [int]$ThrottleLimit, [string]$ReferenceMapFile = '') {
    @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $ScriptPath + '"'),
        '-PhotosPerImage', $PhotosPerImage.ToString([Globalization.CultureInfo]::InvariantCulture),
        '-ThrottleLimit', $ThrottleLimit.ToString([Globalization.CultureInfo]::InvariantCulture)
    )
    if ($ReferenceMapFile) { @('-ReferenceMapFile', ('"' + $ReferenceMapFile + '"')) }
}

function Start-RunProcess([string[]]$ArgumentList, [string]$OutputLog, [string]$ErrorLog) {
    $process = Start-Process powershell.exe -WindowStyle Hidden -PassThru `
        -ArgumentList $ArgumentList -RedirectStandardOutput $OutputLog -RedirectStandardError $ErrorLog
    # Retain the native handle while the process is alive so ExitCode survives exit
    # when Start-Process runs asynchronously under Windows PowerShell 5.1.
    [void]$process.Handle
    return $process
}
function Update-Status { if (-not $script:proc) { $lblStatus.Text = "Sẵn sàng • $(Count-Urls) sản phẩm" } }
function Save-Urls([switch]$RequireReady) {
    Save-ProductQueueEditor $queueEditor $urlFile -RequireReady:$RequireReady
}
function Load-Urls {
    $script:loadingUrls = $true
    try { if (Test-Path $urlFile) { Set-ProductQueueUrls $queueEditor @(Get-Content $urlFile -Encoding UTF8 | Where-Object { $_.Trim() }) } }
    finally { $script:loadingUrls = $false }
    Update-Status
}
# Only explicit user messages are written here. Pipeline output goes through Receive-RunLine.
function Append-Log([string]$text) {
    if ($text) { $txtLog.AppendText($text + "`r`n") }
}

function Update-RunDisplay {
    if (-not $script:proc) { return }
    $elapsed = (Get-Date) - $script:runStarted
    $time = '{0:00}:{1:00}' -f [int][Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
    $activity = @($script:itemStages.GetEnumerator() | Where-Object { $_.Value -notin @('Đã xong', 'Chưa hoàn tất') } | Sort-Object Name | ForEach-Object { "SP $($_.Key): $($_.Value)" })
    if ($script:runStage -eq 'Đang lưu kết quả' -or -not $activity.Count) { $activity = @($script:runStage) }
    $lblProgress.Text = "$($script:runDone)/$($script:runTotal) ảnh đã xong  •  $($activity -join '  |  ')  •  $time"
    # Show each product's live stage on its own row (rows follow queue order, stage index is 1-based).
    # Jobs map to queue rows (a link with several images runs several jobs on one row).
    foreach ($entry in $script:itemStages.GetEnumerator()) {
        $i = if ($script:jobRows.Count -ge [int]$entry.Key) { $script:jobRows[[int]$entry.Key - 1] - 1 } else { [int]$entry.Key - 1 }
        if ($i -ge 0 -and $i -lt $queueEditor.Rows.Count) {
            $status = $queueEditor.Rows[$i].Status
            $done = $entry.Value -eq 'Đã xong'
            $status.Text = if ($done) { '✔ Đã xong' } else { "◔ $($entry.Value)" }
            $status.ForeColor = if ($done) { $ui.Ok } else { $ui.Accent }
        }
    }
}

function Receive-RunLine([string]$line) {
    $event = ConvertTo-UiEvent $line $script:currentIndex
    if (-not $event) { return }
    switch ($event.Kind) {
        'Start' { $script:runTotal = $event.Total; $bar.Maximum = [Math]::Max(1, $event.Total) }
        'Output' { $script:resultFolder = $event.Path }
        'Rows' { $script:jobRows = $event.Rows }
        'Item' { $script:currentIndex = $event.Index; $script:itemStages[$event.Index] = $event.Stage }
        'Stage' { $script:itemStages[$event.Index] = $event.Stage; $script:runStage = $event.Stage }
        'Retry' { $script:itemStages[$event.Index] = $event.Stage }
        'Saving' { $script:runStage = $event.Stage }
        'Completed' {
            if ($script:itemStages[$event.Index] -ne 'Đã xong') { $script:runDone++ }
            $script:itemStages[$event.Index] = $event.Stage
        }
        'Failed' { $script:itemStages[$event.Index] = $event.Stage; $script:hadFailure = $true }
        'Warning' { $script:hadFailure = $true }
        'Tokens' {
            $script:runTokens.In += $event.TokensIn; $script:runTokens.Cached += $event.TokensCached; $script:runTokens.Out += $event.TokensOut; Update-UsageLabel
            # Quota follows the run: re-read it after a call used tokens, at most every 15 seconds.
            if (-not $script:quotaProc -and ((Get-Date) - $script:quotaAt).TotalSeconds -ge 15) { $quotaTimer.Interval = 100 }
        }
    }
    if ($event.Text) { Append-Log $event.Text }
    Update-RunDisplay
}

# An error in a button or window handler goes to workspace/logs/app-errors.log (sent with Gửi lỗi) instead of
# WinForms' generic dialog; the user sees a short message and the app keeps going.
if (-not $BuildOnly) {
    [Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        Write-AppError $workspace.Logs 'Giao diện Windows' $e.Exception
        [void][Windows.Forms.MessageBox]::Show("Có lỗi: $($e.Exception.Message)`r`n`r`nLỗi đã được ghi lại. Bấm Gửi lỗi để gửi cho admin.", 'Product Review Batch', 'OK', 'Warning')
    }.GetNewClosure())
}
$form = New-Object Windows.Forms.Form
$appVersion = try { Get-AppVersion $root } catch { '' }
$form.Text = ('Product Review Batch ' + $appVersion).Trim()
$form.Size = New-Object Drawing.Size(1120, 840)
$form.MinimumSize = New-Object Drawing.Size(1040, 760)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.BackColor=[Drawing.SystemColors]::Control
$ui=$script:Ui; $ink=$ui.Ink; $muted=$ui.Muted
$form.ForeColor=$ink
$appIcon = New-StarIcon
$form.Icon = $appIcon
$tray = New-AppTray $form $appIcon
$tray.Visible = -not $BuildOnly
$form.Add_FormClosed({ $tray.Visible = $false; $tray.Dispose() })
# Each region is a bordered panel on the system-grey page so areas read as separate blocks.
function New-Card([string]$Name,[string]$Heading,[int]$X,[int]$Y,[int]$W,[int]$H,[string]$Anchor='Top,Left') {
    $card=New-Object Windows.Forms.Panel -Property @{Name=$Name;Location=(New-Object Drawing.Point($X,$Y));Size=(New-Object Drawing.Size($W,$H));BackColor=$ui.Page;Anchor=$Anchor}
    $card.Add_Paint({$pen=New-Object Drawing.Pen($script:Ui.Line);try{$_.Graphics.DrawRectangle($pen,0,0,$this.Width-1,$this.Height-1)}finally{$pen.Dispose()}})
    if ($Heading) { $card.Controls.Add((New-Object Windows.Forms.Label -Property @{Text=$Heading;Location='14,10';AutoSize=$true;Font=(New-Object Drawing.Font('Segoe UI',10));ForeColor=$ui.Ink;UseMnemonic=$false})) }
    return $card
}
# Full width before the button is anchored: a docked panel starts 200px wide, which would push a
# right-anchored button past the window edge once the panel stretches.
$header=New-Object Windows.Forms.Panel -Property @{Size=(New-Object Drawing.Size($form.ClientSize.Width,64));Dock='Top';BackColor=$ui.Page}
$title=New-Object Windows.Forms.Label -Property @{Text='Product Review Batch';Location='20,19';AutoSize=$true;Font=(New-Object Drawing.Font('Segoe UI',13));ForeColor=$ink}
$btnUpdate=New-Object Windows.Forms.Button -Property @{Text='Cập nhật';Location='980,16';Size='100,32';Anchor='Top,Right'}
Set-FlatButton $btnUpdate
# Tải về máy runs in the background (src/sync-source.ps1); its progress shows here, in the header, so work goes on.
$syncLabel=New-Object Windows.Forms.Label -Property @{Name='HeaderSync';Location='260,14';Size='700,22';Anchor='Top,Left,Right';ForeColor=$ui.Muted;AutoEllipsis=$true;TextAlign='MiddleRight';Visible=$false}
$syncBar=New-Object Windows.Forms.ProgressBar -Property @{Name='HeaderSyncBar';Location='760,40';Size='200,4';Anchor='Top,Right';Style='Continuous';Visible=$false}
$header.Controls.AddRange(@($btnUpdate,$title,$syncLabel,$syncBar))
# The sync line always ends 12px before the update button, however wide the button is.
function Set-HeaderLayout { $syncLabel.Width = $btnUpdate.Left - 12 - $syncLabel.Left; $syncBar.Left = $btnUpdate.Left - 12 - $syncBar.Width }
Set-HeaderLayout

$cardList=New-Card 'CardProducts' 'Link sản phẩm & ảnh' 20 78 820 344 'Top,Left,Right'
$queueEditor=New-ProductQueueEditor $root
$queueEditor.Panel.Location=[Drawing.Point]::new(14,36)
$queueEditor.Panel.Size=[Drawing.Size]::new(792,296)
$queueEditor.Panel.Anchor='Top,Left,Right'
$queueEditor.Flow.BackColor=$ui.Surface;$queueEditor.Flow.BorderStyle='FixedSingle'
$cardList.Controls.Add($queueEditor.Panel)

$cardActions=New-Card 'CardActions' 'Thao tác' 856 78 224 344 'Top,Right'
# In the order they are used: review the results, open them, then setup and support.
$btnReview=New-Object Windows.Forms.Button -Property @{Text='Duyệt & xuất file';Location='14,36';Size='196,32'}
$btnOut=New-Object Windows.Forms.Button -Property @{Text='Mở kết quả';Location='14,73';Size='196,32'}
$btnSetup=New-Object Windows.Forms.Button -Property @{Text='Kiểm tra cấu hình';Location='14,110';Size='196,32'}
$btnLogs=New-Object Windows.Forms.Button -Property @{Text='Gửi lỗi';Location='14,147';Size='196,32'}
foreach ($b in @($btnReview,$btnOut,$btnSetup,$btnLogs)) { Set-FlatButton $b }
$cardActions.Controls.AddRange(@($btnReview,$btnOut,$btnSetup,$btnLogs))
# Finished images waiting for review: the button shows how many and turns green; nothing pops up.
function Update-ReviewButton {
    $pending = try { Get-PendingReviewCount $script:resultFolder } catch { 0 }
    if ($pending -gt 0) { $btnReview.Text = "Duyệt & xuất file ($pending)"; Set-FlatButton $btnReview -Primary }
    else { $btnReview.Text = 'Duyệt & xuất file'; Set-FlatButton $btnReview }
}

$cardRun=New-Card 'CardRun' '' 20 434 1060 62 'Top,Left,Right'
$btnRun=New-Object Windows.Forms.Button -Property @{Text='Bắt đầu';Location='14,11';Size='160,40'}
$btnStop=New-Object Windows.Forms.Button -Property @{Text='Dừng';Location='186,11';Size='100,40';Enabled=$false}
Set-FlatButton $btnRun -Primary; Set-FlatButton $btnStop
$btnRun.FlatAppearance.BorderSize=0
$lblStatus=New-Object Windows.Forms.Label -Property @{Location='302,18';Size='220,26';AutoEllipsis=$true;ForeColor=$muted;TextAlign='MiddleLeft'}
# Tokens this run has used (added up from each Codex call) and the quota left, refreshed in the background.
$lblTokens=New-Object Windows.Forms.Label -Property @{Name='RunTokens';Location='530,11';Size='370,20';ForeColor=$muted;Font=(New-Object Drawing.Font('Segoe UI',9));TextAlign='MiddleLeft';Anchor='Top,Left,Right';AutoEllipsis=$true}
$lblQuota=New-Object Windows.Forms.Label -Property @{Name='RunQuota';Location='530,31';Size='370,20';ForeColor=$muted;Font=(New-Object Drawing.Font('Segoe UI',9));TextAlign='MiddleLeft';Anchor='Top,Left,Right';AutoEllipsis=$true}
$lblThr=New-Object Windows.Forms.Label -Property @{Text='Luồng:';Location='914,19';Size='56,24';Anchor='Top,Right';ForeColor=$muted}
$numThr=New-Object Windows.Forms.NumericUpDown -Property @{Minimum=1;Maximum=4;Value=2;Location='972,16';Size='64,28';TextAlign='Center';Anchor='Top,Right'}
$cardRun.Controls.AddRange(@($btnRun,$btnStop,$lblStatus,$lblTokens,$lblQuota,$lblThr,$numThr))
$script:runTokens = @{ In = 0L; Cached = 0L; Out = 0L }; $script:quotaText = 'Hạn mức: đang lấy…'
function Format-Count([long]$Value) { $Value.ToString('N0', [Globalization.CultureInfo]::GetCultureInfo('vi-VN')) }
function Update-UsageLabel {
    $t = $script:runTokens
    $tokens = if ($t.In -or $t.Out) { "Token: $(Format-Count ($t.In + $t.Out)) · vào $(Format-Count $t.In) · ra $(Format-Count $t.Out)" } else { 'Token: chưa chạy' }
    $lblTokens.Text = $tokens; $lblQuota.Text = $script:quotaText
}
Update-UsageLabel

$cardLog=New-Card 'CardLog' 'Tiến trình & thông báo' 20 508 1060 282 'Top,Bottom,Left,Right'
$bar=New-Object Windows.Forms.ProgressBar -Property @{Location='14,36';Size='1032,8';Anchor='Top,Left,Right';Style='Blocks'}
$lblProgress=New-Object Windows.Forms.Label -Property @{Text='Thêm sản phẩm và ảnh đi kèm để bắt đầu.';Location='14,50';Size='1032,24';AutoEllipsis=$true;Anchor='Top,Left,Right'}
$txtLog=New-Object Windows.Forms.TextBox -Property @{Multiline=$true;ReadOnly=$true;ScrollBars='Vertical';Location='14,80';Size='1032,188';Anchor='Top,Bottom,Left,Right';BackColor=$ui.Surface;BorderStyle='FixedSingle';Font=(New-Object Drawing.Font('Segoe UI',10))}
$cardLog.Controls.AddRange(@($bar,$lblProgress,$txtLog))

$form.Controls.AddRange(@($cardLog,$cardRun,$cardActions,$cardList,$header))
$lblStatus.Anchor='Top,Left'
$lblThr.Height=$numThr.Height
$btnUpdate.Add_Click({
    if ($script:proc) { [Windows.Forms.MessageBox]::Show($form, 'Đang xử lý sản phẩm. Chờ chạy xong rồi cập nhật.', 'Cập nhật') | Out-Null; return }
    if (Show-UpdateDialog $form $root $workspace.Logs $appVersion) {
        Start-Process powershell -WorkingDirectory $root -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"' + (Join-Path $srcDir 'gui.ps1') + '"'))
        $form.Close()
    }
})
# A newer release shows on the button, green with its version, without updating anything: checked in the
# background a few seconds after the window opens and every 6 hours.
function Set-UpdateButton([string]$Next) {
    $btnUpdate.Text = $(if ($Next) { "Cập nhật $Next" } else { 'Cập nhật' })
    $btnUpdate.Width = $(if ($Next) { 150 } else { 100 })
    $btnUpdate.Left = $header.ClientSize.Width - 24 - $btnUpdate.Width
    Set-FlatButton $btnUpdate -Primary:([bool]$Next)
    Set-HeaderLayout
}
$updateOut = Join-Path $workspace.Logs "update-check-$PID.out"
$script:updateProc = $null
$updateTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 3000 }
$updateTimer.Add_Tick({
    if (-not $script:updateProc) {
        $script:updateProc = Start-Process powershell.exe -WindowStyle Hidden -PassThru -RedirectStandardOutput $updateOut -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $srcDir 'update.ps1') + '"'), '-Root', ('"' + $root + '"'), '-Check')
        [void]$script:updateProc.Handle
        $updateTimer.Interval = 1000
        return
    }
    if (-not $script:updateProc.HasExited) { return }
    $script:updateProc.WaitForExit(); $code = $script:updateProc.ExitCode; $script:updateProc.Dispose(); $script:updateProc = $null
    $next = try { (Get-Content -LiteralPath $updateOut -Raw -ErrorAction Stop).Trim() } catch { '' }
    Remove-Item -LiteralPath $updateOut -Force -ErrorAction SilentlyContinue
    if ($code -eq 0) { Set-UpdateButton $(if ($next -match '^v\d+(\.\d+)*$') { $next } else { '' }) }
    $updateTimer.Interval = 6 * 3600 * 1000
})
if (-not $BuildOnly) { $updateTimer.Start() }
# Quota beside the run, kept current: read when the window opens, every minute, after each run and, while a run goes,
# after calls that used tokens (own process, no waiting).
$quotaOut = Join-Path $workspace.Logs "quota-$PID.out"
$script:quotaProc = $null; $script:quotaAt = [datetime]::MinValue
$quotaTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 2000 }
$quotaTimer.Add_Tick({
    if (-not $script:quotaProc) {
        $script:quotaProc = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $srcDir 'quota-status.ps1') + '"'), '-OutFile', ('"' + $quotaOut + '"'))
        [void]$script:quotaProc.Handle
        $quotaTimer.Interval = 1000
        return
    }
    if (-not $script:quotaProc.HasExited) { return }
    $script:quotaProc.Dispose(); $script:quotaProc = $null; $script:quotaAt = Get-Date
    $text = try { (Get-Content -LiteralPath $quotaOut -Raw -Encoding UTF8 -ErrorAction Stop).Trim() } catch { '' }
    Remove-Item -LiteralPath $quotaOut -Force -ErrorAction SilentlyContinue
    if ($text) { $script:quotaText = $text; Update-UsageLabel }
    $quotaTimer.Interval = 60 * 1000
})
if (-not $BuildOnly) { $quotaTimer.Start() }
$script:syncProc = $null; $script:syncHideAt = $null
$syncStatus = Join-Path $workspace.Logs "sync-status-$PID.json"
function Format-SyncStatus($s) {
    $percent = if ($s.missing) { [int][Math]::Round(100 * $s.done / $s.missing) } else { 0 }
    $where = if (@($s.groups).Count -gt 1) { "$($s.group) ($($s.index)/$(@($s.groups).Count))" } else { [string]$s.group }
    return [pscustomobject]@{ Text = "⟳ Đang tải về máy: $where · $(Format-Count $s.done)/$(Format-Count $s.missing) ảnh"; Percent = $percent }
}
# Starts Tải về máy for these danh mục; $false when one is already running.
function Start-BackgroundSync([string[]]$Names) {
    if ($script:syncProc -or -not @($Names).Count) { return $false }
    Remove-Item -LiteralPath $syncStatus -Force -ErrorAction SilentlyContinue
    $script:syncProc = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $srcDir 'sync-source.ps1') + '"'), '-Group', ('"' + ($Names -join '|') + '"'), '-StatusFile', ('"' + $syncStatus + '"'))
    [void]$script:syncProc.Handle
    $syncLabel.ForeColor = $ui.Muted; $syncLabel.Text = '⟳ Đang tải về máy…'; $syncLabel.Visible = $true; $syncBar.Value = 0; $syncBar.Visible = $true
    $script:syncHideAt = $null; $syncTimer.Start()
    return $true
}
$syncTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 700 }
$syncTimer.Add_Tick({
    if ($script:syncHideAt) { if ((Get-Date) -ge $script:syncHideAt) { $syncLabel.Visible = $false; $script:syncHideAt = $null; $syncTimer.Stop() }; return }
    $s = try { Get-Content -LiteralPath $syncStatus -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { $null }
    if ($s -and -not $s.finished) { $view = Format-SyncStatus $s; $syncLabel.Text = $view.Text; $syncBar.Value = [Math]::Min(100, $view.Percent) }
    if (-not $script:syncProc.HasExited) { return }
    $script:syncProc.Dispose(); $script:syncProc = $null; $syncBar.Visible = $false
    Remove-Item -LiteralPath $syncStatus -Force -ErrorAction SilentlyContinue
    $ok = if ($s) { @($s.groups).Count - @($s.failed).Count } else { 0 }
    $syncLabel.Text = if ($s -and $ok) { "✓ Đã tải về máy $(if (@($s.groups).Count -gt 1) { "$ok danh mục" } else { $s.group }): $(Format-Count $s.total) ảnh (vừa tải $(Format-Count $s.downloaded))$(if (@($s.failed).Count) { " · chưa tải được: $(@($s.failed) -join ', ')" })" } else { "Chưa tải được về máy$(if ($s) { ": $(@($s.failed) -join ', ')" }). Kiểm tra mạng và mật khẩu app." }
    $syncLabel.ForeColor = if ($s -and -not @($s.failed).Count) { $ui.Ok } else { $ui.Error }
    $script:syncHideAt = (Get-Date).AddSeconds(12)
})
$queueEditor | Add-Member -NotePropertyName StartSync -NotePropertyValue { param([string[]]$Names) Start-BackgroundSync $Names } -Force
$btnReview.Add_Click({ if (-not $script:proc) { Show-BatchReviewDialog $form $workspace.Output $script:resultFolder; Update-ReviewButton } })

$btnOut.Add_Click({
    $target = if ($script:resultFolder -and (Test-Path -LiteralPath $script:resultFolder)) { $script:resultFolder } else { $workspace.Output }
    Open-Path $target
})
function Update-CodexPath {
    # npm installs into a folder Windows adds to PATH only for new processes.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
# A fix step runs in its own window (install progress, the sign-in link); the check window reopens after it.
$script:setupProc = $null
$setupTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 1000 }
$setupTimer.Add_Tick({
    if (-not $script:setupProc -or -not $script:setupProc.HasExited) { return }
    $setupTimer.Stop(); $script:setupProc.Dispose(); $script:setupProc = $null
    Update-CodexPath; $btnSetup.Enabled = $true; $btnSetup.PerformClick()
})
function Start-SetupStep([string]$Program, [string[]]$Arguments) {
    $btnSetup.Enabled = $false
    $script:setupProc = Start-Process $Program -ArgumentList $Arguments -PassThru
    $setupTimer.Start()
}
$btnSetup.Add_Click({
    switch (Show-SetupDialog $form $srcDir $workspace.Logs) {
        # Installs whatever is missing (Node.js, Codex, sign-in, browser bridge).
        'install' { Start-SetupStep 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $srcDir 'setup-install.ps1') + '"')) }
        'login' { Start-SetupStep 'cmd.exe' @('/c', 'codex login') }
        'drive' { [void](Show-DriveLogin $form $workspace.Root); $btnSetup.PerformClick() }
    }
})
# The list saves itself on every change; Bắt đầu checks that every link is ready.
# Gửi lỗi: packs the logs and uploads them for the admin page; progress shows on the button.
$script:logsProc = $null
$logsOut = Join-Path $workspace.Logs "send-logs-$PID.out"; $logsErr = Join-Path $workspace.Logs "send-logs-$PID.err"
$logsTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 500 }
$logsReset = New-Object Windows.Forms.Timer -Property @{ Interval = 2500 }
$logsReset.Add_Tick({ $logsReset.Stop(); $btnLogs.Text = 'Gửi lỗi'; $btnLogs.Enabled = -not $script:proc })
$logsTimer.Add_Tick({
    if (-not $script:logsProc.HasExited) { return }
    $logsTimer.Stop(); $script:logsProc.Dispose(); $script:logsProc = $null
    $result = try { (Get-Content -LiteralPath $logsOut -Raw -Encoding UTF8 -ErrorAction Stop).Trim() } catch { '' }
    if ($result -match '^sent\|([^|]+)\|(\d+)$') { $btnLogs.Text = '✓ Đã gửi'; Append-Log "Đã gửi lỗi: $($Matches[1])$(if ([int]$Matches[2]) { " (kèm $($Matches[2]) đánh giá đã Bỏ)" })" }
    elseif ($result -match '^saved\|([^|]+)\|?(.*)$') { $btnLogs.Text = 'Gửi lỗi'; Append-Log "Chưa gửi được ($(if ($Matches[2]) { $Matches[2] } else { 'không rõ lý do' })); file lỗi ở: $($Matches[1])"; Start-Process explorer.exe -ArgumentList ('/select,"' + $Matches[1] + '"') }
    else { $btnLogs.Text = 'Gửi lỗi'; Append-Log 'Chưa tạo được báo cáo lỗi.' }
    $logsReset.Start()
})
$btnLogs.Add_Click({
    $rejected = @(Get-UnsentRejectedSamples $root).Count
    $question = "Gửi lỗi cho admin?`r`n`r`n" + $(if ($rejected) { "Gồm các lỗi từ lần gửi trước và $rejected đánh giá đã Bỏ (kèm lý do)." } else { 'Gồm các lỗi từ lần gửi trước.' }) + ' Không gửi ảnh hay mật khẩu.'
    if ([Windows.Forms.MessageBox]::Show($form, $question, 'Gửi lỗi', 'YesNo') -ne 'Yes') { return }
    $btnLogs.Enabled = $false; $btnLogs.Text = 'Đang gửi…'
    $script:logsProc = Start-Process powershell.exe -WindowStyle Hidden -PassThru -RedirectStandardOutput $logsOut -RedirectStandardError $logsErr -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $srcDir 'send-logs.ps1') + '"'))
    [void]$script:logsProc.Handle
    $logsTimer.Start()
})
$queueEditor.OnChanged={ Update-Status; if (-not $script:loadingUrls) { try { Save-Urls } catch { Write-Verbose $_ } } }

$logFile = Join-Path $workspace.Logs "image-batch-gui-$PID.log"
$errFile = Join-Path $workspace.Logs "image-batch-gui-$PID.err.log"
$script:pos = @{ out = 0L; err = 0L }
$script:lineBuffers = @{ out = ''; err = '' }
function Read-New([string]$path, [string]$key) {
    if (-not (Test-Path $path)) { return }
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
        if ($fs.Length -le $script:pos[$key]) { return }
        $fs.Position = $script:pos[$key]
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $chunk = $sr.ReadToEnd()
        $script:pos[$key] = $fs.Position
    } finally { $fs.Dispose() }
    $lines = (($script:lineBuffers[$key] + $chunk) -split "`r?`n")
    $script:lineBuffers[$key] = $lines[-1]
    for ($i = 0; $i -lt $lines.Count - 1; $i++) { Receive-RunLine $lines[$i] }
}
$timer = New-Object Windows.Forms.Timer -Property @{ Interval = 700 }
$timer.Add_Tick({
    Read-New $logFile 'out'; Read-New $errFile 'err'
    Update-RunDisplay
    if ($script:proc -and $script:proc.HasExited) {
        $script:proc.WaitForExit()
        $script:proc.Refresh()
        Read-New $logFile 'out'; Read-New $errFile 'err'
        foreach ($key in @('out', 'err')) { if ($script:lineBuffers[$key]) { Receive-RunLine $script:lineBuffers[$key]; $script:lineBuffers[$key] = '' } }
        $exitCode = $script:proc.ExitCode
        # Keep the full run log inside its batch so one folder holds everything for that run.
        if ($script:resultFolder -and (Test-Path -LiteralPath $script:resultFolder)) {
            $batchLogs = Join-Path $script:resultFolder 'logs'
            New-Item -ItemType Directory -Force $batchLogs | Out-Null
            foreach ($pair in @(@($logFile, 'run.log'), @($errFile, 'run.err.log'))) {
                if ((Test-Path -LiteralPath $pair[0]) -and (Get-Item -LiteralPath $pair[0]).Length) { Copy-Item -LiteralPath $pair[0] -Destination (Join-Path $batchLogs $pair[1]) -Force }
            }
            Remove-Item -LiteralPath $logFile, $errFile -Force -ErrorAction SilentlyContinue
        }
        $timer.Stop(); $animTimer.Stop(); $script:proc.Dispose(); $script:proc = $null
        $btnRun.Enabled = $true; $btnRun.Text = 'Bắt đầu'; $btnStop.Enabled = $false
        $btnSetup.Enabled = $true; $btnLogs.Enabled = $true; $queueEditor.Panel.Enabled = $true; $numThr.Enabled = $true
        $btnReview.Enabled = $true
        $bar.Style = 'Continuous'; $bar.MarqueeAnimationSpeed = 0
        $bar.Value = [Math]::Min($bar.Maximum, $script:runDone)
        # Finished links leave the queue during the run; their images go too, so the list starts clean.
        $quotaTimer.Interval = 500
        Remove-ManualEntriesExcept $queueEditor.MapPath @(if (Test-Path $urlFile) { Get-Content $urlFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ } })
        Load-Urls
        $elapsed = (Get-Date) - $script:runStarted
        $lblProgress.Text = "Đã xong $($script:runDone)/$($script:runTotal) ảnh • $([int][Math]::Floor($elapsed.TotalMinutes)) phút $($elapsed.Seconds) giây"
        if ($script:runStopped) {
            $lblStatus.Text = 'Đã dừng'; $lblStatus.ForeColor = $ui.Muted; Append-Log 'Đã dừng. Các link chưa hoàn tất được giữ lại.'
        }
        elseif ($null -ne $exitCode -and $exitCode -eq 0 -and -not $script:hadFailure) {
            $lblStatus.Text = '✔ Hoàn tất'; $lblStatus.ForeColor = $ui.Ok
            Append-Log 'Xong. Bấm Duyệt & xuất file để duyệt từng ảnh; file Loox chỉ tạo khi duyệt xong.'
        }
        else {
            $lblStatus.Text = '! Cần thử lại'; $lblStatus.ForeColor = $ui.Warn
            Append-Log 'Một số sản phẩm chưa hoàn tất. Bạn có thể bấm Bắt đầu để thử lại các link còn lại, hoặc Duyệt & xuất file với các ảnh đã xong.'
            Append-Log 'Nếu lỗi lặp lại, bấm Gửi lỗi để admin kiểm tra.'
        }
        Update-ReviewButton
    }
})

# Show running animation only in the status label; button captions stay fixed.
$script:animFrame = 0
$animTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 350 }
$animTimer.Add_Tick({
    if (-not $script:proc) { return }
    $script:animFrame = ($script:animFrame + 1) % 3
    $dots = @('.', '..', '...')[$script:animFrame]
    if (-not $script:runStopped) { $lblStatus.Text = "Đang chạy $dots" }
})
function Start-GuiBatch {
    if ($script:proc) { return }
    if(-not (Get-DriveConfig $workspace.Root)){Append-Log 'Nhập mật khẩu app trước khi chạy (Kiểm tra cấu hình).';return}
    try{Save-Urls -RequireReady}catch{Append-Log $_.Exception.Message;return}
    if (-not (Count-Urls)) { [Windows.Forms.MessageBox]::Show('Vui lòng thêm ít nhất một link sản phẩm.') | Out-Null; return }
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { [Windows.Forms.MessageBox]::Show('Chưa có công cụ xử lý. Bấm "Kiểm tra cấu hình" để xem hướng dẫn.') | Out-Null; return }
    $txtLog.Clear()
    Remove-Item $logFile, $errFile -Force -ErrorAction SilentlyContinue
    $script:pos = @{ out = 0L; err = 0L }
    $script:lineBuffers = @{ out = ''; err = '' }
    $script:runTotal = Count-Urls; $script:runDone = 0; $script:currentIndex = 0
    $script:itemStages = @{}; $script:jobRows = @(); $script:runStage = 'Đang chuẩn bị'; $script:runStopped = $false; $script:hadFailure = $false

    $script:runTokens = @{ In = 0L; Cached = 0L; Out = 0L }; Update-UsageLabel
    $script:runStarted = Get-Date; $script:resultFolder = ''; Update-ReviewButton
    $bar.Maximum = [Math]::Max(1, (Count-Urls)); $bar.Value = 0
    $runArgs = @(New-RunArguments -ScriptPath (Join-Path $srcDir 'run-images.ps1') `
        -PhotosPerImage 1 -ThrottleLimit ([int]$numThr.Value))
    $referenceMapPath=Join-Path $workspace.Root 'reference-inputs/references.json'
    if(Test-Path -LiteralPath $referenceMapPath){$runArgs+=@('-ReferenceMapFile',('"'+$referenceMapPath+'"'))}
    try { $script:proc = Start-RunProcess -ArgumentList $runArgs -OutputLog $logFile -ErrorLog $errFile }
    catch {
        $script:proc=$null
        Append-Log ("Chưa khởi động được lượt xử lý: " + $_.Exception.Message)
        return
    }
    $btnRun.Enabled = $false; $btnStop.Enabled = $true
    $btnSetup.Enabled = $false; $btnLogs.Enabled = $false; $queueEditor.Panel.Enabled = $false; $numThr.Enabled = $false
    $btnReview.Enabled = $false
    $lblStatus.Text = 'Đang chạy'; $lblStatus.ForeColor = $ui.Accent; $bar.Style = 'Marquee'; $bar.MarqueeAnimationSpeed = 30
    Update-RunDisplay
    $timer.Start(); $animTimer.Start()
}
$btnRun.Add_Click({ Start-GuiBatch })
$btnStop.Add_Click({
    if ($script:proc -and -not $script:proc.HasExited) {
        $script:runStopped = $true
        & taskkill.exe /PID $script:proc.Id /T /F | Out-Null
        $lblStatus.Text = 'Đang dừng...'
    }
})

$form.Add_FormClosing({
    if ($script:proc -and -not $script:proc.HasExited) {
        $r = [Windows.Forms.MessageBox]::Show('Đang xử lý sản phẩm. Dừng và đóng ứng dụng?', 'Đóng ứng dụng', 'YesNo')
        if ($r -ne 'Yes') { $_.Cancel = $true; return }
        & taskkill.exe /PID $script:proc.Id /T /F | Out-Null
    }
})

Load-Urls
if(-not $BuildOnly){[void]$form.ShowDialog()}
