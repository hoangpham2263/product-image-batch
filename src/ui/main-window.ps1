# Desktop GUI for run-images.ps1: URL queue, run/stop, live log (Vietnamese), folder shortcuts.
param([switch]$BuildOnly)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'progress.ps1')
. (Join-Path $PSScriptRoot 'help.ps1')

$srcDir = Split-Path $PSScriptRoot -Parent
$root = Split-Path $srcDir -Parent   # project root (base data and local workspace)
. (Join-Path $srcDir 'application/workspace.ps1')
$workspace = Initialize-ProjectWorkspace $root
. (Join-Path $srcDir 'infrastructure/source-catalog.ps1')
. (Join-Path $srcDir 'application/agent-lessons.ps1')
. (Join-Path $srcDir 'application/image-feedback.ps1')
. (Join-Path $srcDir 'application/manual-references.ps1')
. (Join-Path $PSScriptRoot 'image-feedback.ps1')
. (Join-Path $PSScriptRoot 'manual-references.ps1')
$urlFile = $workspace.Queue
$script:proc = $null
$script:resultFolder = ''
$script:currentIndex = 0
$script:itemStages = @{}

$script:activeFeedbackFile = ''

function Open-Path([string]$p) { New-Item -ItemType Directory -Force $p | Out-Null; Start-Process explorer.exe $p }
function Count-Urls { @(Get-ProductQueueUrls $queueEditor).Count }

function New-RunArguments([string]$ScriptPath, [int]$PhotosPerImage, [int]$ThrottleLimit, [string]$FeedbackFile = '', [string]$ApprovedImage = '', [string]$ReferenceMapFile = '') {
    @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $ScriptPath + '"'),
        '-PhotosPerImage', $PhotosPerImage.ToString([Globalization.CultureInfo]::InvariantCulture),
        '-ThrottleLimit', $ThrottleLimit.ToString([Globalization.CultureInfo]::InvariantCulture)
    )
    if ($FeedbackFile) { @('-FeedbackFile', ('"' + $FeedbackFile + '"')) }
    if ($ApprovedImage) { @('-ApprovedImage', ('"' + $ApprovedImage + '"')) }
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
    $lblProgress.Text = "$($script:runDone)/$($script:runTotal) sản phẩm đã xong  •  $($activity -join '  |  ')  •  $time"
}

function Receive-RunLine([string]$line) {
    $event = ConvertTo-UiEvent $line $script:currentIndex
    if (-not $event) { return }
    switch ($event.Kind) {
        'Start' { $script:runTotal = $event.Total; $bar.Maximum = [Math]::Max(1, $event.Total) }
        'Output' { $script:resultFolder = $event.Path }
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
$form.Text = 'Product Image Batch'
$form.Size = New-Object Drawing.Size(1120, 840)
$form.MinimumSize = New-Object Drawing.Size(1040, 760)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.BackColor=[Drawing.SystemColors]::Control
$title=New-Object Windows.Forms.Label -Property @{Text='Sản phẩm & ảnh tham khảo';Location='16,12';AutoSize=$true;Font=(New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Regular))}
$btnSave=New-Object Windows.Forms.Button -Property @{Text='Lưu danh sách';Location='856,48';Size='232,32';Anchor='Top,Right'}
$btnOut=New-Object Windows.Forms.Button -Property @{Text='Mở kết quả';Location='856,88';Size='232,32';Anchor='Top,Right'}
$btnFeedback=New-Object Windows.Forms.Button -Property @{Text='Kiểm tra ảnh / Làm lại';Location='856,128';Size='232,32';Anchor='Top,Right'}
$btnSetup=New-Object Windows.Forms.Button -Property @{Text='Kiểm tra ChatGPT';Location='856,168';Size='232,32';Anchor='Top,Right'}
$btnHelp=New-Object Windows.Forms.Button -Property @{Text='Hướng dẫn';Location='856,208';Size='232,32';Anchor='Top,Right'}
$queueEditor=New-ProductQueueEditor $root
$queueEditor.Panel.Location=[Drawing.Point]::new(16,44)
$queueEditor.Panel.Size=[Drawing.Size]::new(824,342)
$queueEditor.Panel.Anchor='Top,Left,Right'
$btnRun=New-Object Windows.Forms.Button -Property @{Text='Bắt đầu';Location='16,404';Size='160,40';BackColor=[Drawing.Color]::FromArgb(40,140,80);ForeColor=[Drawing.Color]::White;FlatStyle='Flat'}
$btnStop=New-Object Windows.Forms.Button -Property @{Text='Dừng';Location='188,404';Size='100,40';Enabled=$false}
$lblStatus=New-Object Windows.Forms.Label -Property @{Location='304,412';Size='220,26';AutoEllipsis=$true}
$lblPer=New-Object Windows.Forms.Label -Property @{Text='Ảnh từ kho/SP:';Location='626,412';Size='110,24';Anchor='Top,Right'}
$numPer=New-Object Windows.Forms.NumericUpDown -Property @{Minimum=1;Maximum=6;Value=1;Location='738,408';Size='64,28';TextAlign='Center';Anchor='Top,Right'}
$lblThr=New-Object Windows.Forms.Label -Property @{Text='Luồng:';Location='830,412';Size='56,24';Anchor='Top,Right'}
$numThr=New-Object Windows.Forms.NumericUpDown -Property @{Minimum=1;Maximum=4;Value=1;Location='890,408';Size='64,28';TextAlign='Center';Anchor='Top,Right'}
$lblThreadHint=New-Object Windows.Forms.Label -Property @{Text='Thêm sản phẩm → dán link và ảnh trong popup → Lưu → Bắt đầu. Khuyên dùng 1–2 luồng.';Location='16,452';Size='1076,22';ForeColor=[Drawing.Color]::DimGray;Anchor='Top,Left,Right'}
$bar=New-Object Windows.Forms.ProgressBar -Property @{Location='16,482';Size='1076,12';Anchor='Top,Left,Right';Style='Blocks'}
$lblProgress=New-Object Windows.Forms.Label -Property @{Text='Thêm sản phẩm và ảnh đi kèm để bắt đầu.';Location='16,504';Size='1076,24';AutoEllipsis=$true;Anchor='Top,Left,Right'}
$btnClear=New-Object Windows.Forms.Button -Property @{Text='Xóa thông báo';Location='856,248';Size='232,32';Anchor='Top,Right'}
$txtLog=New-Object Windows.Forms.TextBox -Property @{Multiline=$true;ReadOnly=$true;ScrollBars='Vertical';Location='16,536';Size='1076,256';Anchor='Top,Bottom,Left,Right';BackColor=[Drawing.Color]::White}
$form.Controls.AddRange(@($title,$btnSave,$btnOut,$btnSetup,$btnHelp,$btnFeedback,$queueEditor.Panel,$btnRun,$btnStop,$lblStatus,$lblPer,$numPer,$lblThr,$numThr,$lblThreadHint,$bar,$lblProgress,$btnClear,$txtLog))
$lblStatus.Anchor='Top,Left'
$lblPer.Height=$numPer.Height;$lblThr.Height=$numThr.Height
$lblPer.Visible=$queueEditor.Fallback.Checked;$numPer.Visible=$queueEditor.Fallback.Checked
$queueEditor.Fallback.Add_CheckedChanged({$lblPer.Visible=$queueEditor.Fallback.Checked;$numPer.Visible=$queueEditor.Fallback.Checked})
$btnHelp.Add_Click({ Show-AppHelp $form })
$btnClear.Add_Click({ $txtLog.Clear() })
$btnFeedback.Add_Click({
    if ($script:proc) { return }
    $selection = Show-ImageFeedbackDialog $form $root $workspace.Output
    if ($selection.ApprovedImage) { Start-GuiBatch -ApprovedImage $selection.ApprovedImage }
    elseif ($selection.FeedbackPath) { Start-GuiBatch -FeedbackFile $selection.FeedbackPath }
})

$btnSave.Add_Click({try{Save-Urls;Update-Status;Append-Log 'Đã lưu danh sách link và ảnh đi kèm.'}catch{Append-Log $_.Exception.Message}})
$btnOut.Add_Click({
    $target = if ($script:resultFolder -and (Test-Path -LiteralPath $script:resultFolder)) { $script:resultFolder } else { $workspace.Output }
    Open-Path $target
})
$btnSetup.Add_Click({
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
    } catch {
        Append-Log 'Chưa kiểm tra được ChatGPT. Vui lòng thử lại hoặc xem setup.txt.'
    } finally { $form.Cursor = 'Default'; $btnSetup.Enabled = $true }
})
$queueEditor.OnChanged={ Update-Status }

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
        $timer.Stop(); $script:proc.Dispose(); $script:proc = $null
        $btnRun.Enabled = $true; $btnRun.Text = 'Bắt đầu'; $btnStop.Enabled = $false
        $btnSave.Enabled = $true; $btnSetup.Enabled = $true; $queueEditor.Panel.Enabled = $true; $numPer.Enabled = $true; $numThr.Enabled = $true
        $btnFeedback.Enabled = $true
        $bar.Style = 'Continuous'; $bar.MarqueeAnimationSpeed = 0
        $bar.Value = [Math]::Min($bar.Maximum, $script:runDone)
        Load-Urls
        $elapsed = (Get-Date) - $script:runStarted
        $lblProgress.Text = "Đã xong $($script:runDone)/$($script:runTotal) sản phẩm • $([int][Math]::Floor($elapsed.TotalMinutes)) phút $($elapsed.Seconds) giây"
        if ($script:runStopped) {
            if ($script:activeFeedbackFile) { Set-ImageFeedbackStatus $script:activeFeedbackFile stopped $script:resultFolder }
            $lblStatus.Text = 'Đã dừng'; Append-Log 'Đã dừng. Các link chưa hoàn tất được giữ lại.'
        }
        elseif ($null -ne $exitCode -and $exitCode -eq 0 -and -not $script:hadFailure) {
            $lblStatus.Text = 'Hoàn tất'
            if ($script:activeFeedbackFile) { Append-Log 'Đã có ảnh làm lại. Bấm Kiểm tra ảnh / Làm lại để đối chiếu; chỉ đánh dấu đã đúng sau khi bạn xem ảnh.' }
            else { Append-Log 'Kết quả đã được lưu. Bấm Mở kết quả để xem ảnh và đánh giá.' }
        }
        else {
            $lblStatus.Text = 'Cần thử lại'
            Append-Log 'Một số sản phẩm chưa hoàn tất. Bạn có thể bấm Bắt đầu để thử lại các link còn lại.'
        }
    }
})

function Start-GuiBatch([string]$FeedbackFile = '', [string]$ApprovedImage = '') {
    if ($script:proc) { return }
    if (-not $FeedbackFile -and -not $ApprovedImage) { try{Save-Urls -RequireReady}catch{Append-Log $_.Exception.Message;return} }
    if (-not $FeedbackFile -and -not $ApprovedImage -and -not (Count-Urls)) { [Windows.Forms.MessageBox]::Show('Vui lòng thêm ít nhất một link sản phẩm.') | Out-Null; return }
    if (-not $ApprovedImage -and -not (Get-Command codex -ErrorAction SilentlyContinue)) { [Windows.Forms.MessageBox]::Show('Chưa có công cụ xử lý. Bấm "Kiểm tra ChatGPT" để xem hướng dẫn.') | Out-Null; return }
    $txtLog.Clear()
    Remove-Item $logFile, $errFile -Force -ErrorAction SilentlyContinue
    $script:pos = @{ out = 0L; err = 0L }
    $script:lineBuffers = @{ out = ''; err = '' }
    $script:activeFeedbackFile = $FeedbackFile
    $script:runTotal = if ($FeedbackFile -or $ApprovedImage) { 1 } else { Count-Urls }; $script:runDone = 0; $script:currentIndex = 0
    $script:itemStages = @{}; $script:runStage = 'Đang chuẩn bị'; $script:runStopped = $false; $script:hadFailure = $false

    $script:runStarted = Get-Date; $script:resultFolder = ''
    $bar.Maximum = [Math]::Max(1, (Count-Urls)); $bar.Value = 0
    $runArgs = @(New-RunArguments -ScriptPath (Join-Path $srcDir 'run-images.ps1') `
        -PhotosPerImage ([int]$numPer.Value) -ThrottleLimit ([int]$numThr.Value) -FeedbackFile $FeedbackFile -ApprovedImage $ApprovedImage)
    $referenceMapPath=Join-Path $workspace.Root 'reference-inputs/references.json'
    if(-not $FeedbackFile -and -not $ApprovedImage -and (Test-Path -LiteralPath $referenceMapPath)){$runArgs+=@('-ReferenceMapFile',('"'+$referenceMapPath+'"'))}
    try { $script:proc = Start-RunProcess -ArgumentList $runArgs -OutputLog $logFile -ErrorLog $errFile }
    catch {
        $script:proc=$null
        if ($FeedbackFile) { Set-ImageFeedbackStatus $FeedbackFile failed '' $_.Exception.Message }
        Append-Log ("Chưa khởi động được lượt xử lý: " + $_.Exception.Message)
        return
    }
    $btnRun.Enabled = $false; $btnRun.Text = 'Đang chạy...'; $btnStop.Enabled = $true
    $btnSave.Enabled = $false; $btnSetup.Enabled = $false; $queueEditor.Panel.Enabled = $false; $numPer.Enabled = $false; $numThr.Enabled = $false
    $btnFeedback.Enabled = $false
    $lblStatus.Text = 'Đang chạy...'; $bar.Style = 'Marquee'; $bar.MarqueeAnimationSpeed = 30
    Update-RunDisplay
    $timer.Start()
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
        if ($script:activeFeedbackFile) { Set-ImageFeedbackStatus $script:activeFeedbackFile stopped $script:resultFolder }
    }
})

Load-Urls
if(-not $BuildOnly){[void]$form.ShowDialog()}
