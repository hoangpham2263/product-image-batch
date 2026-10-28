# One product: steps 1-5. BatchWorkflow runs steps 6-7 after workers finish.
function Invoke-ProductItem($Item, [string]$ItemId, $Brands) {
    $script:Config.ActiveProductUrl = $Item.Url
    $script:Config.ActiveScene = if ($Item.PSObject.Properties['Scene']) { $Item.Scene } else { $null }
    if ($script:Config.Feedback) {
        $feedback = $script:Config.Feedback
        if ($Item.Url -ne $feedback.Record.product_url) { throw 'Feedback URL mismatch.' }
        $savedProduct = @($feedback.Manifest.images | Where-Object role -eq product)[0]
        $sourceProduct = Resolve-FeedbackChild (Join-Path $feedback.Folder 'refs') $savedProduct.file
        $savedContext = $feedback.Manifest.product_context
        if (-not $savedContext) { $savedContext = Resolve-ProductContext $Item.Handle $sourceProduct $ItemId }
        $product = [pscustomobject]@{Reference=$sourceProduct;Context=$savedContext}
        Write-Host '  [PRODUCT] Reusing original product and room for user correction...' -ForegroundColor Cyan
    } else { $product = Read-ProductInput $Item $ItemId }
    $download = $product.Reference
    try {
        try {
            if ($script:Config.Feedback) {
                $picked = @($feedback.Manifest.images | Where-Object { $_.role -in @('scene','subject') } | ForEach-Object { Resolve-FeedbackChild (Join-Path $feedback.Folder 'refs') $_.file })
                if (-not $picked.Count) { throw 'No suitable archived room found for correction.' }
            } else { $picked = @(Select-ProductReferences $product.Reference $Item.Handle $ItemId $product.Context) }
        }
        catch {
            if ($_.Exception.Message -notmatch 'No suitable') { throw }
            Save-MissingData $Item $ItemId $product.Context $product.Reference $_.Exception.Message
            throw "[CAUSE:MISSING_DATA] No suitable sample photo for $($product.Context.product). Recorded in missing-data."
        }
        $request = New-ProductImageRequest $product.Reference $ItemId $product.Context $picked $Brands
        if ($script:Config.Feedback) {
            $request.Images = @($request.Images) + @($feedback.RejectedImage)
            $request | Add-Member NoteProperty RejectedInput $feedback.RejectedImage
            $request.Prompt += "`nImage $($request.Images.Count) is the REJECTED RESULT, supplied only to identify the user's complaint. Do not use it as the product or room source. Correct the requested problem using the original product and room inputs."
            Write-FeedbackJson (Join-Path $script:Batch.Logs "$ItemId-user-feedback.json") $feedback.Record
        }
        $bundle = Save-ProductReferenceBundle $Item $ItemId $product.Context $request $picked.Count
        $product.Reference = $bundle.ProductPath
        $reply = Complete-ProductImage $request $product.Context $ItemId
    } finally {
        # The downloaded original is archived as refs/<item>/NN-product; drop the loose copy.
        if ((Split-Path $download -Parent) -eq $script:Batch.Refs -and (Test-Path -LiteralPath $download)) { Remove-Item -LiteralPath $download -Force }
    }
    if ($reply -match '(?im)^BRAND:\s*(.+)$' -and $Matches[1].Trim() -notmatch '^(?i)none$') { [void]$Brands.Add($Matches[1].Trim()) }
    $body = New-Review $Item.Url $Item.Handle $request.Output $ItemId $product.Context
    # With Drive configured the CSV carries the public Drive link; the local file stays in the batch.
    $photoUrl = $request.Output -replace '\\', '/'
    if ($script:Config.Drive) {
        try {
            $photoUrl = Publish-ImageToDrive $request.Output $script:Batch.Id $Item.Handle
            Write-Host "  [DRIVE] $photoUrl" -ForegroundColor Cyan
        } catch { Write-Warning "[DRIVE] Upload failed; CSV keeps the local path. $($_.Exception.Message)" }
    }
    [pscustomobject][ordered]@{
        product_handle = $Item.Handle
        rating = ''
        author = ''
        email = ''
        body = $body
        created_at = ''
        verified_purchase = 'true'
        photo_url = $photoUrl
        photo_path = ($request.Output -replace '\\', '/')
    }
}
