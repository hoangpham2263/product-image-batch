function New-WorkflowConfiguration([string]$ProjectRoot, [string]$SourceDir, [int]$MaxTries, [int]$PhotosPerImage, [string]$Model) {
    $workspace = Initialize-ProjectWorkspace $ProjectRoot
    $contexts = @(Get-ProductContexts (Join-Path $ProjectRoot 'data/product-contexts.json'))
    $catalog = Get-SourceCatalog $SourceDir
    # Review categories come from every catalog entry, including groups not downloaded from Drive.
    $allPhotos = @{}
    foreach ($entry in @(Get-SampleCatalogEntries $SourceDir)) { $allPhotos[$entry.file] = $entry }
    return @{
        SourceDir = $SourceDir; MaxTries = $MaxTries; Model = $Model; PhotosPerImage = $PhotosPerImage
        ReviewStyles = @(Get-ReviewStyleProfiles (Join-Path $ProjectRoot 'data/review-style.json'))
        ReviewSamples = @(Get-ReviewSamples (Join-Path $ProjectRoot 'data/review-samples.jsonl') $contexts $allPhotos)
        StyleExample = Join-Path $ProjectRoot 'data/image-style/example.png'
        ProductContexts = $contexts
        SourceCatalog = $catalog
        AgentInstructionsPath = Join-Path $ProjectRoot 'AGENTS.md'
        FeedbackRoot = Join-Path $workspace.Root 'feedback'
        Drive = Get-DriveConfig $workspace.Root
        DeliveryRoot = Join-Path $workspace.Root 'delivery-pending'
        WritingStyle = Get-WritingStyle (Join-Path $ProjectRoot 'data/writing-style.json')
    }
}
