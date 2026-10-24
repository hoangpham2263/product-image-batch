# One product: steps 1-5. BatchWorkflow runs steps 6-7 after workers finish.
function Invoke-ProductItem($Item, [string]$ItemId, $Brands) {
    $product = Read-ProductInput $Item $ItemId
    $download = $product.Reference
    try {
        try { $picked = @(Select-ProductReferences $product.Reference $Item.Handle $ItemId $product.Context) }
        catch {
            if ($_.Exception.Message -notmatch 'No suitable') { throw }
            Save-MissingData $Item $ItemId $product.Context $product.Reference $_.Exception.Message
            throw "[CAUSE:MISSING_DATA] No suitable sample photo for $($product.Context.product). Recorded in missing-data."
        }
        $request = New-ProductImageRequest $product.Reference $ItemId $product.Context $picked $Brands
        $bundle = Save-ProductReferenceBundle $Item $ItemId $product.Context $request $picked.Count
        $product.Reference = $bundle.ProductPath
        $reply = Complete-ProductImage $request $product.Reference $product.Context $ItemId
    } finally {
        # The downloaded original is archived as refs/<item>/NN-product; drop the loose copy.
        if ((Split-Path $download -Parent) -eq $script:Batch.Refs -and (Test-Path -LiteralPath $download)) { Remove-Item -LiteralPath $download -Force }
    }
    if ($reply -match '(?im)^BRAND:\s*(.+)$' -and $Matches[1].Trim() -notmatch '^(?i)none$') { [void]$Brands.Add($Matches[1].Trim()) }
    $body = New-Review $Item.Url $Item.Handle $request.Output $ItemId $product.Context
    [pscustomobject][ordered]@{
        product_handle = $Item.Handle
        rating = ''
        author = ''
        email = ''
        body = $body
        created_at = ''
        verified_purchase = 'true'
        photo_url = ($request.Output -replace '\\', '/')
        photo_path = ($request.Output -replace '\\', '/')
    }
}
