function New-WorkflowConfiguration([string]$ProjectRoot, [string]$SourceDir, [int]$MaxTries, [int]$PhotosPerImage, [string]$Model) {
    $workspace = Initialize-ProjectWorkspace $ProjectRoot
    return @{
        SourceDir = $SourceDir; MaxTries = $MaxTries; Model = $Model; PhotosPerImage = $PhotosPerImage
        ReviewStyles = @(Get-ReviewStyleProfiles (Join-Path $ProjectRoot 'data/review-style.json'))
        StyleExample = Join-Path $ProjectRoot 'data/image-style/example.png'
        ProductContexts = @(Get-ProductContexts (Join-Path $ProjectRoot 'data/product-contexts.json'))
        SourceCatalog = Get-SourceCatalog $SourceDir
        WritingStyle = Get-WritingStyle (Join-Path $ProjectRoot 'data/writing-style.json')
    }
}
