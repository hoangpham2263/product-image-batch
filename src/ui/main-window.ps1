# Desktop GUI for run-images.ps1: URL queue, run/stop, live log (Vietnamese), folder shortcuts.
param([switch]$BuildOnly)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'progress.ps1')
. (Join-Path $PSScriptRoot 'drive-login.ps1')

$srcDir = Split-Path $PSScriptRoot -Parent
$root = Split-Path $srcDir -Parent   # project root (base data and local workspace)
. (Join-Path $srcDir 'application/workspace.ps1')
. (Join-Path $srcDir 'infrastructure/platform.ps1')
. (Join-Path $srcDir 'infrastructure/drive-storage.ps1')
$workspace = Initialize-ProjectWorkspace $root
. (Join-Path $srcDir 'infrastructure/source-catalog.ps1')
. (Join-Path $srcDir 'infrastructure/source-sync.ps1')
. (Join-Path $srcDir 'application/agent-lessons.ps1')
. (Join-Path $srcDir 'application/image-feedback.ps1')
. (Join-Path $srcDir 'application/manual-references.ps1')
. (Join-Path $srcDir 'infrastructure/csv.ps1')
. (Join-Path $srcDir 'application/batch-review.ps1')
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
    if (Test-Path $urlFile) { Set-ProductQueueUrls $queueEditor @(Get-Content $urlFile -Encoding UTF8 | Where-Object { $_.Trim() }) }
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
    }
    if ($event.Text) { Append-Log $event.Text }
    Update-RunDisplay
}

$form = New-Object Windows.Forms.Form
$appVersion = try { (Get-Content -LiteralPath (Join-Path $workspace.Root 'version.txt') -Raw -ErrorAction Stop).Trim() } catch { '' }
$form.Text = ('Product Review Batch ' + $appVersion).Trim()
$form.Size = New-Object Drawing.Size(1120, 840)
$form.MinimumSize = New-Object Drawing.Size(1040, 760)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.BackColor=[Drawing.SystemColors]::Control
$ui=$script:Ui; $ink=$ui.Ink; $muted=$ui.Muted
$form.ForeColor=$ink
# Each region is a bordered panel on the system-grey page so areas read as separate blocks.
function New-Card([string]$Name,[string]$Heading,[int]$X,[int]$Y,[int]$W,[int]$H,[string]$Anchor='Top,Left') {
    $card=New-Object Windows.Forms.Panel -Property @{Name=$Name;Location=(New-Object Drawing.Point($X,$Y));Size=(New-Object Drawing.Size($W,$H));BackColor=$ui.Page;Anchor=$Anchor}
    $card.Add_Paint({$pen=New-Object Drawing.Pen($script:Ui.Line);try{$_.Graphics.DrawRectangle($pen,0,0,$this.Width-1,$this.Height-1)}finally{$pen.Dispose()}})
    if ($Heading) { $card.Controls.Add((New-Object Windows.Forms.Label -Property @{Text=$Heading;Location='14,10';AutoSize=$true;Font=(New-Object Drawing.Font('Segoe UI',10));ForeColor=$ui.Ink;UseMnemonic=$false})) }
    return $card
}
$header=New-Object Windows.Forms.Panel -Property @{Dock='Top';Height=64;BackColor=$ui.Page}
$title=New-Object Windows.Forms.Label -Property @{Text='Product Review Batch';Location='20,20';AutoSize=$true;Font=(New-Object Drawing.Font('Segoe UI',13));ForeColor=$ink}
$btnUpdate=New-Object Windows.Forms.Button -Property @{Text='Cập nhật';Location='980,18';Size='100,28';Anchor='Top,Right'}
Set-FlatButton $btnUpdate
$header.Controls.AddRange(@($title,$btnUpdate))

$cardList=New-Card 'CardProducts' 'Link sản phẩm & ảnh đi kèm' 20 78 820 344 'Top,Left,Right'
$queueEditor=New-ProductQueueEditor $root
$queueEditor.Panel.Location=[Drawing.Point]::new(14,36)
$queueEditor.Panel.Size=[Drawing.Size]::new(792,296)
$queueEditor.Panel.Anchor='Top,Left,Right'
$queueEditor.Flow.BackColor=$ui.Surface;$queueEditor.Flow.BorderStyle='FixedSingle'
$cardList.Controls.Add($queueEditor.Panel)

$cardActions=New-Card 'CardActions' 'Thao tác' 856 78 224 344 'Top,Right'
$btnSave=New-Object Windows.Forms.Button -Property @{Text='Lưu danh sách';Location='14,36';Size='196,32'}
$btnOut=New-Object Windows.Forms.Button -Property @{Text='Mở kết quả';Location='14,73';Size='196,32'}
$btnReview=New-Object Windows.Forms.Button -Property @{Text='Duyệt & xuất file';Location='14,110';Size='196,32'}
$btnSetup=New-Object Windows.Forms.Button -Property @{Text='Kiểm tra ChatGPT';Location='14,147';Size='196,32'}
$btnDrive=New-Object Windows.Forms.Button -Property @{Text='Google Drive';Location='14,184';Size='196,32'}
foreach ($b in @($btnSave,$btnOut,$btnReview,$btnSetup,$btnDrive)) { Set-FlatButton $b }
$cardActions.Controls.AddRange(@($btnSave,$btnOut,$btnReview,$btnSetup,$btnDrive))
# Finished images waiting for review: the button shows how many and turns green; nothing pops up.
function Update-ReviewButton {
    $pending = try { Get-PendingReviewCount $script:resultFolder } catch { 0 }
    if ($pending -gt 0) { $btnReview.Text = "Duyệt & xuất file ($pending)"; Set-FlatButton $btnReview -Primary }
    else { $btnReview.Text = 'Duyệt & xuất file'; Set-FlatButton $btnReview }
}
function Update-DriveButton { $btnDrive.Text = if (Test-Path -LiteralPath (Join-Path $workspace.Root 'drive.json')) { 'Google Drive ✓' } else { 'Google Drive' } }
Update-DriveButton

$cardRun=New-Card 'CardRun' '' 20 434 1060 62 'Top,Left,Right'
$btnRun=New-Object Windows.Forms.Button -Property @{Text='Bắt đầu';Location='14,11';Size='160,40'}
$btnStop=New-Object Windows.Forms.Button -Property @{Text='Dừng';Location='186,11';Size='100,40';Enabled=$false}
Set-FlatButton $btnRun -Primary; Set-FlatButton $btnStop
$btnRun.FlatAppearance.BorderSize=0
$lblStatus=New-Object Windows.Forms.Label -Property @{Location='302,18';Size='220,26';AutoEllipsis=$true;ForeColor=$muted;TextAlign='MiddleLeft'}
$lblPer=New-Object Windows.Forms.Label -Property @{Text='Ảnh từ kho/SP:';Location='720,19';Size='110,24';Anchor='Top,Right';ForeColor=$muted}
$numPer=New-Object Windows.Forms.NumericUpDown -Property @{Minimum=1;Maximum=1;Value=1;Location='832,16';Size='64,28';TextAlign='Center';Anchor='Top,Right'}
$lblThr=New-Object Windows.Forms.Label -Property @{Text='Luồng:';Location='914,19';Size='56,24';Anchor='Top,Right';ForeColor=$muted}
$numThr=New-Object Windows.Forms.NumericUpDown -Property @{Minimum=1;Maximum=4;Value=1;Location='972,16';Size='64,28';TextAlign='Center';Anchor='Top,Right'}
$cardRun.Controls.AddRange(@($btnRun,$btnStop,$lblStatus,$lblPer,$numPer,$lblThr,$numThr))

$cardLog=New-Card 'CardLog' 'Tiến trình & thông báo' 20 508 1060 282 'Top,Bottom,Left,Right'
$bar=New-Object Windows.Forms.ProgressBar -Property @{Location='14,36';Size='1032,8';Anchor='Top,Left,Right';Style='Blocks'}
$lblProgress=New-Object Windows.Forms.Label -Property @{Text='Thêm sản phẩm và ảnh đi kèm để bắt đầu.';Location='14,50';Size='1032,24';AutoEllipsis=$true;Anchor='Top,Left,Right'}
$txtLog=New-Object Windows.Forms.TextBox -Property @{Multiline=$true;ReadOnly=$true;ScrollBars='Vertical';Location='14,80';Size='1032,188';Anchor='Top,Bottom,Left,Right';BackColor=$ui.Surface;BorderStyle='FixedSingle';Font=(New-Object Drawing.Font('Segoe UI',10))}
$cardLog.Controls.AddRange(@($bar,$lblProgress,$txtLog))

$form.Controls.AddRange(@($cardLog,$cardRun,$cardActions,$cardList,$header))
$lblStatus.Anchor='Top,Left'
$lblPer.Height=$numPer.Height;$lblThr.Height=$numThr.Height
$lblPer.Visible=$queueEditor.Fallback.Checked;$numPer.Visible=$queueEditor.Fallback.Checked
$queueEditor.Fallback.Add_CheckedChanged({$lblPer.Visible=$queueEditor.Fallback.Checked;$numPer.Visible=$queueEditor.Fallback.Checked})
$btnDrive.Add_Click({ [void](Show-DriveLogin $form $workspace.Root); Update-DriveButton })
$btnUpdate.Add_Click({
    if ($script:proc) { [Windows.Forms.MessageBox]::Show($form, 'Đang xử lý sản phẩm. Chờ chạy xong rồi cập nhật.', 'Cập nhật') | Out-Null; return }
    $updater = Join-Path $root 'src\update.ps1'
    $form.Cursor = 'WaitCursor'
    try { $next = & $updater -Root $root -Check }
    catch { $next = $null; $err = $_.Exception.Message }
    finally { $form.Cursor = 'Default' }
    if ($null -eq $next) { [Windows.Forms.MessageBox]::Show($form, "Không kiểm tra được bản mới: $err", 'Cập nhật') | Out-Null; return }
    if (-not $next) { [Windows.Forms.MessageBox]::Show($form, 'Đang dùng bản mới nhất.', 'Cập nhật') | Out-Null; return }
    $label = if ($next -eq 'git') { 'mới' } else { $next }
    if ([Windows.Forms.MessageBox]::Show($form, "Có bản $label. Cập nhật và mở lại app?", 'Cập nhật', 'YesNo') -ne 'Yes') { return }
    Start-Process powershell -WorkingDirectory $root -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"' + $updater + '"'),'-Restart','-WaitPid',$PID)
    $form.Close()
})
$btnReview.Add_Click({ if (-not $script:proc) { Show-BatchReviewDialog $form $workspace.Output $script:resultFolder; Update-ReviewButton } })

$btnSave.Add_Click({try{Save-Urls;Update-Status;Append-Log 'Đã lưu danh sách link và ảnh đi kèm.'}catch{Append-Log $_.Exception.Message}})
$btnOut.Add_Click({
    $target = if ($script:resultFolder -and (Test-Path -LiteralPath $script:resultFolder)) { $script:resultFolder } else { $workspace.Output }
    Open-Path $target
})
# Kiểm tra ChatGPT turns into Cài Codex / Đăng nhập Codex when the check finds that step missing.
$script:setupAction = ''
function Set-SetupButton([string]$Action) {
    $script:setupAction = $Action
    switch ($Action) {
        'install' { $btnSetup.Text = 'Cài Codex'; Set-FlatButton $btnSetup -Primary }
        'login' { $btnSetup.Text = 'Đăng nhập Codex'; Set-FlatButton $btnSetup -Primary }
        default { $btnSetup.Text = 'Kiểm tra ChatGPT'; Set-FlatButton $btnSetup }
    }
}
function Update-CodexPath {
    # npm installs into a folder Windows adds to PATH only for new processes.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
# Runs a setup step in its own console window (npm progress, the Codex sign-in link), then checks again.
$script:setupProc = $null
$setupTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 1000 }
$setupTimer.Add_Tick({
    if (-not $script:setupProc -or -not $script:setupProc.HasExited) { return }
    $setupTimer.Stop(); $script:setupProc.Dispose(); $script:setupProc = $null
    Update-CodexPath; $btnSetup.Enabled = $true; Set-SetupButton ''; $btnSetup.PerformClick()
})
function Start-SetupStep([string]$Program, [string[]]$Arguments, [string]$Message) {
    Append-Log $Message
    $btnSetup.Enabled = $false
    $script:setupProc = Start-Process $Program -ArgumentList $Arguments -PassThru
    $setupTimer.Start()
}
$btnSetup.Add_Click({
    # Installs whatever is missing (Node.js, Codex, sign-in, browser bridge) in its own window.
    if ($script:setupAction -eq 'install') { Start-SetupStep 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $srcDir 'setup-install.ps1') + '"')) 'Đang cài Node.js, Codex và đăng nhập ChatGPT trong cửa sổ mới; xong app tự kiểm tra lại.'; return }
    if ($script:setupAction -eq 'login') { Start-SetupStep 'cmd.exe' @('/c', 'codex login') 'Đăng nhập ChatGPT trong trình duyệt vừa mở; xong app tự kiểm tra lại.'; return }
    $btnSetup.Enabled = $false; $form.Cursor = 'WaitCursor'
    $txtLog.Clear(); Append-Log 'Đang kiểm tra ChatGPT...'
    $outFile = Join-Path $workspace.Logs "image-batch-setup-$PID.log"
    $setupError = Join-Path $workspace.Logs "image-batch-setup-$PID.err.log"
    try {
        $setupArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $srcDir 'setup-check.ps1') + '"'), '-AsJson')
        Start-Process powershell.exe -WindowStyle Hidden -Wait -ArgumentList $setupArgs -RedirectStandardOutput $outFile -RedirectStandardError $setupError
        $report = Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($check in $report.Checks) {
            Append-Log $check.Message
            if (-not $check.Ok -and $check.Action) { Append-Log $check.Action }
        }
        Append-Log $report.Summary
        Set-SetupButton $report.NextAction
    } catch {
        Append-Log 'Chưa kiểm tra được ChatGPT. Vui lòng thử lại hoặc xem setup.txt.'
    } finally { $form.Cursor = 'Default'; $btnSetup.Enabled = $true }
})
$queueEditor.OnChanged={ Update-Status }
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { Set-SetupButton 'install' }

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
        $btnSave.Enabled = $true; $btnSetup.Enabled = $true; $queueEditor.Panel.Enabled = $true; $numPer.Enabled = $true; $numThr.Enabled = $true
        $btnDrive.Enabled = $true; $btnReview.Enabled = $true
        $bar.Style = 'Continuous'; $bar.MarqueeAnimationSpeed = 0
        $bar.Value = [Math]::Min($bar.Maximum, $script:runDone)
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
    if(-not (Get-DriveConfig $workspace.Root)){Append-Log 'Đăng nhập Google Drive trước khi chạy để CSV có link ảnh công khai.';return}
    try{Save-Urls -RequireReady}catch{Append-Log $_.Exception.Message;return}
    if (-not (Count-Urls)) { [Windows.Forms.MessageBox]::Show('Vui lòng thêm ít nhất một link sản phẩm.') | Out-Null; return }
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { [Windows.Forms.MessageBox]::Show('Chưa có công cụ xử lý. Bấm "Kiểm tra ChatGPT" để xem hướng dẫn.') | Out-Null; return }
    $txtLog.Clear()
    Remove-Item $logFile, $errFile -Force -ErrorAction SilentlyContinue
    $script:pos = @{ out = 0L; err = 0L }
    $script:lineBuffers = @{ out = ''; err = '' }
    $script:runTotal = Count-Urls; $script:runDone = 0; $script:currentIndex = 0
    $script:itemStages = @{}; $script:jobRows = @(); $script:runStage = 'Đang chuẩn bị'; $script:runStopped = $false; $script:hadFailure = $false

    $script:runStarted = Get-Date; $script:resultFolder = ''; Update-ReviewButton
    $bar.Maximum = [Math]::Max(1, (Count-Urls)); $bar.Value = 0
    $runArgs = @(New-RunArguments -ScriptPath (Join-Path $srcDir 'run-images.ps1') `
        -PhotosPerImage ([int]$numPer.Value) -ThrottleLimit ([int]$numThr.Value))
    $referenceMapPath=Join-Path $workspace.Root 'reference-inputs/references.json'
    if(Test-Path -LiteralPath $referenceMapPath){$runArgs+=@('-ReferenceMapFile',('"'+$referenceMapPath+'"'))}
    try { $script:proc = Start-RunProcess -ArgumentList $runArgs -OutputLog $logFile -ErrorLog $errFile }
    catch {
        $script:proc=$null
        Append-Log ("Chưa khởi động được lượt xử lý: " + $_.Exception.Message)
        return
    }
    $btnRun.Enabled = $false; $btnStop.Enabled = $true
    $btnSave.Enabled = $false; $btnSetup.Enabled = $false; $queueEditor.Panel.Enabled = $false; $numPer.Enabled = $false; $numThr.Enabled = $false
    $btnDrive.Enabled = $false; $btnReview.Enabled = $false
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
