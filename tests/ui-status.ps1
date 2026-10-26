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
    if ($txtLog.Text -notmatch 'Sản phẩm 2 đã hoàn tất' -or $lblProgress.Text -notmatch '1/2 sản phẩm đã xong') { throw 'Missing user-facing status.' }
    if ((ConvertTo-UiEvent '  [RETRY] AI busy; attempt 2/3 in 3s...  (#1)').Text -notmatch 'tự thử lại') { throw 'Retry guidance missing.' }
    if ((ConvertTo-UiEvent 'WARNING: [ITEM 1] Failed; URL and source kept for retry. No suitable real scene reference was found').Text -notmatch 'chưa tìm được ảnh mẫu thực tế') { throw 'Missing-data failure needs a clear user message.' }
    foreach ($case in @(@('MISSING_DATA','thiếu ảnh mẫu'), @('PRODUCT_TIMEOUT','3 lần thử'), @('PRODUCT_NETWORK','Kiểm tra mạng'), @('PRODUCT_ACCESS','chặn truy cập'), @('PRODUCT_NOT_FOUND','không tìm thấy'), @('PRODUCT_DOWNLOAD','chưa tải được'), @('STORE_LOCKED','cửa hàng đang bật mật khẩu'), @('AUTH','đăng nhập'), @('QUOTA','hết hạn mức'), @('NETWORK','Internet'), @('BUSY','thử lại sau'))) {
        $event = ConvertTo-UiEvent "WARNING: [ITEM 1] Failed; URL and source kept for retry. AI failed. Details: C:\private\error.log [CAUSE:$($case[0])]"
        if ($event.Text -notmatch $case[1] -or $event.Text -match 'CAUSE|C:\\|Details') { throw 'Account/network errors leaked technical text or lacked user guidance.' }
    }
    if ((ConvertTo-UiEvent '  [DOWNLOAD-RETRY] Attempt 2/3...  (#1)').Text -notmatch 'Đang tự thử tải lại') { throw 'Product download retry was hidden from the user.' }
    if ((ConvertTo-UiEvent '  [REFERENCE-COUNT] Using 1 checked reference(s) and their real setting.').Text -notmatch 'dùng 1 ảnh mẫu') { throw 'Reduced reference count was not explained.' }
    if ((ConvertTo-UiEvent '[AI-CONNECTION] Connection interrupted').Text -notmatch '60 giây') { throw 'Live connection interruption is hidden.' }
    if ((ConvertTo-UiEvent '[AI-RESUMED] Response stream resumed.').Text -notmatch 'phản hồi trở lại') { throw 'Connection recovery is hidden.' }
    if ((ConvertTo-UiEvent '[AI-WAIT] 90/480s elapsed.').Stage -notmatch '90/480') { throw 'AI waiting time is hidden.' }
    if ((ConvertTo-UiEvent 'WARNING: [ITEM 1] Failed; [CAUSE:AI_TIMEOUT] AI failed').Text -notmatch 'quá thời gian chờ') { throw 'AI deadline must be explained.' }
    if ((ConvertTo-UiEvent '[QUALITY-REASON] FAIL: The tabletop is too pale and grain is missing.').Text -notmatch 'too pale') { throw 'The concrete reason for repair was hidden.' }
    if ((ConvertTo-UiEvent 'WARNING: [ITEM 1] Failed; Image quality check failed: FAIL: The tabletop is too pale.').Text -notmatch 'too pale') { throw 'The final rejection reason was hidden.' }
    $fullReason='Angular compositing seams; chair fragments remain; mask exposes unrelated floor.'
    Receive-RunLine "[QUALITY-REASON] FAIL: $fullReason (#1)"
    Receive-RunLine 'WARNING: [ITEM 1] Failed; Image quality check failed: FAIL: Angular compositing seams'
    if($txtLog.Lines[-2] -notmatch [regex]::Escape($fullReason) -or $txtLog.Lines[-2] -match '\(#1\)'){throw 'Wrapped final warnings lost the complete quality reason or leaked worker tags.'}
    Write-Host 'PASS: parallel live status, completed count, user messages, retry guidance, and diagnostic filtering.' -ForegroundColor Green
} finally {
    $txtLog.Dispose(); $lblProgress.Dispose(); $bar.Dispose()
}
