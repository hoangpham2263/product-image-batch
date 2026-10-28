# Human check of every result before the final CSV: decisions live in <batch>/review.json.
function Save-BatchResults($Rows, [string]$BatchDir) {
    if (-not $BatchDir) { return }
    $json = ConvertTo-Json -InputObject @($Rows) -Depth 5
    [IO.File]::WriteAllText((Join-Path $BatchDir 'results.json'), $json, [Text.UTF8Encoding]::new($false))
}

function Get-BatchReview([string]$BatchDir) {
    $resultsPath = Join-Path $BatchDir 'results.json'
    if (-not (Test-Path -LiteralPath $resultsPath)) { return @() }
    $rows = @(Get-Content -LiteralPath $resultsPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    $decisions = @{}
    $reviewPath = Join-Path $BatchDir 'review.json'
    if (Test-Path -LiteralPath $reviewPath) {
        (Get-Content -LiteralPath $reviewPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $decisions[$_.Name] = $_.Value }
    }
    foreach ($row in $rows) {
        $id = [IO.Path]::GetFileNameWithoutExtension([string]$row.photo_path)
        $product = ''
        try { $product = (Get-FeedbackTarget ([string]$row.photo_path)).ProductPath } catch { Write-Verbose $_ }
        [pscustomobject]@{ Id = $id; Row = $row; ImagePath = [string]$row.photo_path; ProductPath = $product; Decision = [string]$decisions[$id] }
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
    $path = Join-Path $BatchDir 'loox_import_final.csv'
    Save-Csv @($ok.Row) $path
    return $path
}
