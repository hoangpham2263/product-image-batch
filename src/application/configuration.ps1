function New-WorkflowConfiguration([string]$ProjectRoot, [string]$SourceDir, [int]$MaxTries, [int]$PhotosPerImage, [string]$Model) {
    $workspace = Initialize-ProjectWorkspace $ProjectRoot
    $contexts = @(Get-ProductContexts (Join-Path $ProjectRoot 'data/product-contexts.json'))
    $catalog = Get-SourceCatalog $SourceDir
    return @{
        SourceDir = $SourceDir; MaxTries = $MaxTries; Model = $Model; PhotosPerImage = $PhotosPerImage
        ReviewStyles = @(Get-ReviewStyleProfiles (Join-Path $ProjectRoot 'data/review-style.json'))
        ReviewSamples = @(Get-ReviewSamples (Join-Path $ProjectRoot 'data/review-samples.jsonl') $contexts $catalog)
        StyleExample = Join-Path $ProjectRoot 'data/image-style/example.png'
        ProductContexts = $contexts
        SourceCatalog = $catalog
        WritingStyle = Get-WritingStyle (Join-Path $ProjectRoot 'data/writing-style.json')
    }
}
