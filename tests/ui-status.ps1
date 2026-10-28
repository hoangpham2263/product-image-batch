$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/ui/progress.ps1')
Add-Type -AssemblyName System.Windows.Forms
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/ui/main-window.ps1'), [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors | Out-String) }
foreach ($name in @('Append-Log', 'Update-RunDisplay', 'Receive-RunLine')) {
    $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
$txtLog = New-Object Windows.Forms.TextBox
$txtLog.Multiline = $true
$lblProgress = New-Object Windows.Forms.Label
$bar = New-Object Windows.Forms.ProgressBar
$script:proc = [pscustomobject]@{ Running = $true }
$script:runStarted = Get-Date
$script:runTotal = 0; $script:runDone = 0; $script:currentIndex = 0
$script:itemStages = @{}; $script:runStage = 'Đang chuẩn bị'; $script:hadFailure = $false
try {
    $lines = @(
        'Starting: 2 URLs',
        'Batch: C:\private\output\batch',
        'Threads: 2',
        '[1/2] product-one',
        '  [SELECT] Subject reference...  (#1)',
        '  [CHECK 1/5] C:\private\people.jpg  (#1)',
        '  [SKIP] Not suitable  (#1)',
        '[2/2] product-two',
        '  [IMAGE] Creating one complete scene...  (#2)',
        '  [IMAGE] Creating one complete scene...  (#1)',
        '  [REVIEW] Generating text...  (#2)',
        '  [OK] [ITEM 2] C:\private\result.png',
        'WARNING: [ITEM 1] Failed; URL and source kept for retry. AI failed. Details: C:\private\logs\error.txt',
        '    + CategoryInfo : InvalidData: NativeCommandError',
        '    + FullyQualifiedErrorId : ParameterArgumentTransformationError',
        '  [METADATA] Assigning random review fields locally...',
        'Done: 1/2 exported in 350s',
        'CSV: C:\private\output.csv',
        'History: C:\private\history',
        'Pending: C:\private\urls.txt'
    )
    foreach ($line in $lines) { Receive-RunLine $line }
    if ($script:runDone -ne 1 -or $script:runTotal -ne 2 -or -not $script:hadFailure) { throw 'Incorrect parallel completion/error status.' }
    if ($script:itemStages[2] -ne 'Đã xong' -or $script:itemStages[1] -ne 'Chưa hoàn tất') { throw 'Parallel item attribution failed.' }
    if ($script:resultFolder -ne 'C:\private\output\batch') { throw 'Result folder was not retained for the open button.' }
    if ($txtLog.Text -match 'C:\\|#\d|CHECK|NativeCommandError|CategoryInfo|METADATA|product-one') { throw 'Technical details leaked into user messages.' }
    if ($txtLog.Text -notmatch 'Sản phẩm 2: xong' -or $lblProgress.Text -notmatch '1/2 ảnh đã xong') { throw 'Missing user-facing status.' }
    if ((ConvertTo-UiEvent '  [RETRY] AI busy; attempt 2/3 in 3s...  (#1)').Text -notmatch 'tự thử lại') { throw 'Retry guidance missing.' }
    if ((ConvertTo-UiEvent 'WARNING: [ITEM 1] Failed; URL and source kept for retry. No suitable real scene reference was found').Text -notmatch 'chưa tìm được ảnh mẫu') { throw 'Missing-data failure needs a clear user message.' }
    foreach ($case in @(@('MISSING_DATA','thiếu ảnh mẫu'), @('PRODUCT_TIMEOUT','quá chậm'), @('PRODUCT_NETWORK','Kiểm tra mạng'), @('PRODUCT_ACCESS','chặn truy cập'), @('PRODUCT_NOT_FOUND','không tìm thấy'), @('PRODUCT_DOWNLOAD','chưa tải được'), @('STORE_LOCKED','cửa hàng có mật khẩu'), @('AUTH','đăng nhập'), @('QUOTA','hết hạn mức'), @('NETWORK','Mất mạng'), @('BUSY','thử lại sau'), @('DRIVE_UPLOAD','không tạo ảnh mới'), @('DRIVE_AUTH','Đăng nhập lại'), @('DRIVE_CONFIG','Đăng nhập lại'))) {
        $event = ConvertTo-UiEvent "WARNING: [ITEM 1] Failed; URL and source kept for retry. AI failed. Details: C:\private\error.log [CAUSE:$($case[0])]"
        if ($event.Text -notmatch $case[1] -or $event.Text -match 'CAUSE|C:\\|Details') { throw 'Account/network errors leaked technical text or lacked user guidance.' }
    }
    if ((ConvertTo-UiEvent '  [DOWNLOAD-RETRY] Attempt 2/3...  (#1)').Text -notmatch 'Đang tự thử tải lại') { throw 'Product download retry was hidden from the user.' }
    if ((ConvertTo-UiEvent '[AI-CONNECTION] Connection interrupted').Text -notmatch '60 giây') { throw 'Live connection interruption is hidden.' }
    if ((ConvertTo-UiEvent '[AI-WAIT] 90/480s elapsed.').Stage -notmatch '90/480') { throw 'AI waiting time is hidden.' }
    if ((ConvertTo-UiEvent '[IMAGE-RETRY] AI_TIMEOUT 2/3').Text -notmatch '2/3') { throw 'Automatic image retry count is hidden.' }
    if ((ConvertTo-UiEvent '[IMAGE-ATTEMPT] 3/3').Stage -notmatch '3/3') { throw 'Current image attempt is hidden.' }
    if ((ConvertTo-UiEvent '[IMAGE-RECOVERED] Saved image found').Stage -notmatch 'kiểm tra ảnh đã lưu') { throw 'Recovered image validation is hidden.' }
    if ((ConvertTo-UiEvent 'WARNING: [ITEM 1] Failed; [CAUSE:AI_TIMEOUT] AI failed').Text -notmatch 'quá thời gian chờ') { throw 'AI deadline must be explained.' }
    $quotaEvent=ConvertTo-UiEvent 'WARNING: [ITEM 1] Failed; [CAUSE:QUOTA] usage_limit_reached; HTTP 429; Message: The usage limit has been reached; Reset: 09:34:10 29/10/2026 (UTC+7); Details: C:\private\trace.log'
    if($quotaEvent.Text -notmatch 'HTTP 429' -or $quotaEvent.Text -notmatch '09:34:10 29/10/2026' -or $quotaEvent.Text -notmatch 'The usage limit has been reached' -or $quotaEvent.Text -match 'private'){throw 'UI hid service quota details or leaked local diagnostic paths.'}
    $missingEvent=ConvertTo-UiEvent 'WARNING: [ITEM 1] Failed; [CAUSE:OUTPUT_MISSING] Output image not found'
    if($missingEvent.Text -notmatch 'nguyên nhân chưa rõ' -or $missingEvent.Text -match 'hết hạn mức'){throw 'Missing output was incorrectly labeled quota exhaustion.'}
    $questionEvent=ConvertTo-UiEvent 'WARNING: [ITEM 1] Failed; [CAUSE:OUTPUT_MISSING] AI_REPLY: Should I replace their worn polos?; Details: C:\private\trace.log'
    if($questionEvent.Text -notmatch 'Should I replace their worn polos' -or $questionEvent.Text -match 'private'){throw 'AI question was hidden behind an unknown PNG error.'}
    foreach($legacy in @('[QUALITY] Checking','[REFINE] Improving','[QUALITY-REASON] FAIL: obsolete')){if(ConvertTo-UiEvent $legacy){throw 'Retired visual QA events are still active.'}}
    Write-Host 'PASS: parallel live status, completed count, user messages, retry guidance, and diagnostic filtering.' -ForegroundColor Green
} finally {
    $txtLog.Dispose(); $lblProgress.Dispose(); $bar.Dispose()
}
