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

function Set-BatchReviewDecision([string]$BatchDir, [string]$Id, [ValidateSet('ok', 'bad', '')][string]$Decision) {
    $path = Join-Path $BatchDir 'review.json'
    $saved = [ordered]@{}
    if (Test-Path -LiteralPath $path) { (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $saved[$_.Name] = $_.Value } }
    if ($Decision) { $saved[$Id] = $Decision } else { $saved.Remove($Id) }
    [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $saved), [Text.UTF8Encoding]::new($false))
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
