. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
$dir = Join-Path $root 'data/source-photos'
$catalog = Get-SourceCatalog $dir
if ($catalog.Count -lt 202) { throw 'Expected at least the 202 preserved photos.' }
$hashes = @{}
foreach ($path in $catalog.Keys) {
    $entry = $catalog[$path]
    if ($entry.file -notmatch '^[a-z][a-z0-9-]*/[^/]+$') { throw 'Photo is outside product categories.' }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hash -ine $entry.sha256 -or $hashes.ContainsKey($hash)) { throw 'Changed or duplicate photo.' }
    $hashes[$hash] = $true
}
$expansionPath = Join-Path $root 'data/dining-gallery-expansion.json'
if (Test-Path -LiteralPath $expansionPath) {
    $expansion = Get-Content -LiteralPath $expansionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $newPhotos = @($catalog.Values | Where-Object collection_id -eq $expansion.collection_id)
    if ($newPhotos.Count -ne $expansion.photos_added -or @($newPhotos | Where-Object { -not $_.visual_checked -or [Math]::Min($_.width, $_.height) -lt 600 }).Count) { throw 'Dining expansion is incomplete or contains unchecked/undersized photos.' }
    foreach ($check in $expansion.fit_checks) {
        $photo = $catalog[[IO.Path]::GetFullPath((Join-Path $dir $check.file))]
        if (-not $photo -or -not @($photo.fit_checks | Where-Object { $_.product_sha256 -eq $check.product_sha256 -and $_.verdict -eq $check.verdict }).Count) { throw 'Dining fit evidence does not match the library.' }
    }
    if (@($expansion.fit_checks | Where-Object verdict -eq FIT).Count -lt 6) { throw 'Missing checked room alternatives for the twelve-chair product.' }
}
$script:Config = @{ SourceDir = $dir; SourceCatalog = $catalog; MaxTries = 1; ProductContexts = @(Get-ProductContexts (Join-Path $root 'data/product-contexts.json')) }
$script:Batch = @{ Logs = $TestWorkspaceRoot }
function Invoke-AI($PromptText, $Images, $ResultFile) {
    $entry = $script:Config.SourceCatalog[$Images[0]]
    if ($entry.category -ne 'polo-shirts' -or $entry.source_kind -eq 'review') { throw 'Category/provenance selection priority failed.' }
    return 'FIT'
}
Select-Photo 'product.png' 'polo-shirt' 'catalog-test' | Out-Null
Write-Host "PASS: $($catalog.Count) unique photos, provenance hashes and category selection."
