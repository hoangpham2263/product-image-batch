# Runs keep their rows in <batch>/results.json; the Loox CSV is written only after every image
# is reviewed (decisions in <batch>/review.json).
function Save-BatchResults($Rows, [string]$BatchDir) {
    if (-not $BatchDir) { return }
    $json = ConvertTo-Json -InputObject @($Rows) -Depth 5
    [IO.File]::WriteAllText((Join-Path $BatchDir 'results.json'), $json, [Text.UTF8Encoding]::new($false))
}

function Get-BatchReview([string]$BatchDir) {
    $resultsPath = Join-Path $BatchDir 'results.json'
    if (-not (Test-Path -LiteralPath $resultsPath)) { return @() }
    # Windows PowerShell returns a JSON array as one pipeline object. Assign it
    # directly before iterating so several reviews are never collapsed into one row.
    $rows = Get-Content -LiteralPath $resultsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $decisions = @{}
    $reviewPath = Join-Path $BatchDir 'review.json'
    if (Test-Path -LiteralPath $reviewPath) {
        (Get-Content -LiteralPath $reviewPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $decisions[$_.Name] = $_.Value }
    }
    foreach ($row in @($rows)) {
        $id = [IO.Path]::GetFileNameWithoutExtension([string]$row.photo_path)
        $target = $null
        try { $target = Get-FeedbackTarget ([string]$row.photo_path) } catch { Write-Verbose $_ }
        [pscustomobject]@{ Id = $id; Row = $row; ImagePath = [string]$row.photo_path; ProductPath = [string]$target.ProductPath; ScenePath = [string]$target.ScenePath; Decision = [string]$decisions[$id] }
    }
}

# $RejectedRoot defaults to workspace/rejected next to workspace/output (see Save-RejectedSample).
function Set-BatchReviewDecision([string]$BatchDir, [string]$Id, [ValidateSet('ok', 'bad', '')][string]$Decision, [string]$RejectedRoot) {
    $path = Join-Path $BatchDir 'review.json'
    $saved = [ordered]@{}
    if (Test-Path -LiteralPath $path) { (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $saved[$_.Name] = $_.Value } }
    if ($Decision) { $saved[$Id] = $Decision } else { $saved.Remove($Id) }
    [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $saved), [Text.UTF8Encoding]::new($false))
    if (-not $RejectedRoot) { $RejectedRoot = Join-Path (Split-Path (Split-Path ([IO.Path]::GetFullPath($BatchDir)) -Parent) -Parent) 'rejected' }
    $sample = Join-Path $RejectedRoot ((Split-Path $BatchDir -Leaf) + '__' + $Id)
    if ($Decision -eq 'bad') {
        $item = @(Get-BatchReview $BatchDir | Where-Object Id -eq $Id)
        if ($item.Count) { Save-RejectedSample $item[0] $BatchDir $sample }
    } elseif ((Test-Path -LiteralPath $sample) -and -not (Test-Path -LiteralPath (Join-Path $sample '.sent'))) {
        Remove-Item -LiteralPath $sample -Recurse -Force
    }
}

# A review marked Bỏ is kept as data to improve the images, in workspace/rejected/<run>__<id>/: the result, the
# product photo, the original review photo, the run's manifest and what was written. It outlives the run folder;
# Gửi log sends the samples not sent yet and marks them with .sent. Choosing again before that drops the copy.
function Save-RejectedSample($Item, [string]$BatchDir, [string]$Folder) {
    New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    foreach ($pair in @(@($Item.ImagePath, 'result'), @($Item.ProductPath, 'product'), @($Item.ScenePath, 'review'), @((Join-Path $BatchDir "refs/$($Item.Id)/manifest.json"), 'manifest'))) {
        if ($pair[0] -and (Test-Path -LiteralPath $pair[0])) { Copy-Item -LiteralPath $pair[0] -Destination (Join-Path $Folder ($pair[1] + [IO.Path]::GetExtension($pair[0]))) -Force }
    }
    $info = [ordered]@{ run = (Split-Path $BatchDir -Leaf); id = $Item.Id; product_handle = [string]$Item.Row.product_handle; rating = [string]$Item.Row.rating
        body = [string]$Item.Row.body; decision = 'bad'; decided_at = (Get-Date).ToString('o') }
    [IO.File]::WriteAllText((Join-Path $Folder 'sample.json'), (ConvertTo-Json -InputObject $info), [Text.UTF8Encoding]::new($false))
}

# Samples marked Bỏ that Gửi log has not sent yet, oldest first.
function Get-UnsentRejectedSamples([string]$ProjectRoot) {
    $root = Join-Path $ProjectRoot 'workspace/rejected'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    return @(Get-ChildItem -LiteralPath $root -Directory | Where-Object { -not (Test-Path -LiteralPath (Join-Path $_.FullName '.sent')) } | Sort-Object LastWriteTime)
}

function Complete-RejectedSamples([string[]]$Folders) {
    foreach ($folder in @($Folders)) { if (Test-Path -LiteralPath $folder) { [IO.File]::WriteAllText((Join-Path $folder '.sent'), (Get-Date).ToString('o')) } }
}

# Only after every image has a decision; only images marked ok go into the file.
function Export-ReviewedCsv([string]$BatchDir) {
    $items = @(Get-BatchReview $BatchDir)
    if (-not $items.Count) { throw 'Lần chạy này chưa có ảnh nào.' }
    $left = @($items | Where-Object { -not $_.Decision })
    if ($left.Count) { throw "Còn $($left.Count) ảnh chưa duyệt." }
    $ok = @($items | Where-Object Decision -eq 'ok')
    if (-not $ok.Count) { throw 'Chưa có ảnh nào Đạt.' }
    $path = Join-Path $BatchDir 'loox_import.csv'
    Save-Csv @($ok.Row) $path
    return $path
}

# Images still waiting for a decision in one run folder (0 when nothing to review).
function Get-PendingReviewCount([string]$BatchDir) {
    if (-not $BatchDir -or -not (Test-Path -LiteralPath (Join-Path $BatchDir 'results.json'))) { return 0 }
    return @(Get-BatchReview $BatchDir | Where-Object { -not $_.Decision }).Count
}
