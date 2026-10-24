# Products without a suitable sample photo are recorded for the next library update.
# <batch>/missing-data/<item>/ holds the product image and info.json; missing-data.csv lists them all.
function Save-MissingData($Item, [string]$ItemId, $Context, [string]$ProductImage, [string]$Reason) {
    $folder = Join-Path $script:Batch.MissingData $ItemId
    New-Item -ItemType Directory -Force $folder | Out-Null
    if ($ProductImage -and (Test-Path -LiteralPath $ProductImage)) {
        Copy-Item -LiteralPath $ProductImage -Destination (Join-Path $folder ('product' + [IO.Path]::GetExtension($ProductImage)))
    }
    $info = [ordered]@{
        item_id = $ItemId; product_url = $Item.Url; product_handle = $Item.Handle
        product = $Context.product; presentation = $Context.presentation
        categories = (@($Context.source_categories) -join ';'); setting = $Context.setting
        reason = $Reason; recorded_at = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText((Join-Path $folder 'info.json'), ($info | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}

function Write-MissingDataSummary($Batch) {
    if (-not (Test-Path -LiteralPath $Batch.MissingData)) { return }
    $rows = @(Get-ChildItem -LiteralPath $Batch.MissingData -Recurse -Filter 'info.json' | Sort-Object FullName |
        ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } |
        Select-Object item_id, product, categories, presentation, product_url)
    if (-not $rows.Count) { return }
    $csv = Join-Path $Batch.Dir 'missing-data.csv'
    $rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    Write-Host "Missing data: $($rows.Count) product(s). $csv" -ForegroundColor Yellow
}
