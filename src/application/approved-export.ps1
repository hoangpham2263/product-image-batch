# Explicit human acceptance is a separate completion path.
function Export-ApprovedProduct([string]$ProjectRoot, [string]$ImagePath, [string]$OutDir) {
    $started=Get-Date
    $target=Get-FeedbackTarget $ImagePath
    $manifest=$target.Manifest
    $itemId=$manifest.item_id
    $script:Config.ActiveProductUrl=$manifest.product_url
    $context=$manifest.product_context
    $script:Batch=New-Batch $OutDir
    Write-Host 'Starting: 1 URLs'
    Write-Host "Batch: $($script:Batch.Dir)"
    Write-Host "[1/1] $itemId"
    Write-Host '  [HUMAN-APPROVED] Exporting the image explicitly accepted by the user; no new generation or AI image verdict.' -ForegroundColor Cyan
    $handle=([Uri]$manifest.product_url).AbsolutePath.TrimEnd('/').Split('/')[-1]
    if(-not $context){$context=Resolve-ProductContext $handle $target.ProductPath $itemId}
    $picked=@($manifest.images|Where-Object{$_.role -in @('scene','subject')}|ForEach-Object{Resolve-FeedbackChild $target.Folder $_.file})
    # Verify all archived inputs before constructing a new, independent handover.
    foreach($entry in $manifest.images){
        $source=Resolve-FeedbackChild $target.Folder $entry.file
        if((Get-BytesHash ([IO.File]::ReadAllBytes($source))) -ine $entry.sha256){throw 'Archived input has changed; approved export stopped.'}
    }
    $request=New-ProductImageRequest $target.ProductPath $itemId $context $picked ([Collections.ArrayList]::new())
    $request.Images=@($request.Images)+@($target.ImagePath)
    $request|Add-Member NoteProperty ApprovedInput $target.ImagePath
    $item=[pscustomobject]@{Url=$manifest.product_url;Handle=$handle}
    $bundle=Save-ProductReferenceBundle $item $itemId $context $request $picked.Count
    Copy-Item -LiteralPath $target.ImagePath -Destination $request.Output
    $evidence=[ordered]@{
        schema_version=1;completion_method='explicit_user_approval';ai_image_qa_passed=$false
        approved_at=[DateTime]::UtcNow.ToString('o');source_image=$target.ImagePath
        source_sha256=Get-BytesHash ([IO.File]::ReadAllBytes($target.ImagePath))
        output_sha256=Get-BytesHash ([IO.File]::ReadAllBytes($request.Output))
        pixel_change_policy='Byte-for-byte copy of the image explicitly approved by the user. No image processing.'
        product_url=$manifest.product_url;source_batch=$target.Batch;source_feedback_id=$manifest.feedback_id
    }
    Write-FeedbackJson (Join-Path $script:Batch.Dir 'user-approval.json') $evidence
    Write-Lines $script:Batch.InputUrls @($item.Url)
    # Keep the accepted image usable even if the optional draft text service is unavailable.
    try{$body=New-Review $item.Url $handle $request.Output $itemId $context}
    catch{
        $_|Out-String|Set-Content -LiteralPath (Join-Path $script:Batch.Logs "$itemId-review-error.txt") -Encoding UTF8
        $body=''
        Write-Warning 'Approved image saved; review text unavailable and left blank for manual entry.'
    }
    $row=[pscustomobject]@{product_handle=$handle;rating='';author='';email='';body=$body;created_at='';verified_purchase='false';photo_url=($request.Output -replace '\\','/');photo_path=($request.Output -replace '\\','/')}
    Complete-ReviewMetadata @($row) (Join-Path $ProjectRoot 'data/names.txt')
    # Human image acceptance is not evidence of a verified customer purchase.
    $row.verified_purchase='false'
    Save-Csv @($row) $script:Batch.Csv
    Write-Lines $script:Batch.CompletedUrls @($item.Url)
    Write-Host "  [OK] [ITEM 1] $($request.Output)"
    Write-Host ("Done: 1/1 exported in {0}s" -f [int]((Get-Date)-$started).TotalSeconds)
    Write-Host "CSV: $($script:Batch.Csv)"
    return $script:Batch.Dir
}
