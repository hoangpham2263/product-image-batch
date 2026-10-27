# Batch pipeline: one product URL per line in urls.txt. Each run creates a timestamped batch.
# For every URL: load product, select subject/scene references, create one photo, write a review.
# URLs are processed in parallel (-ThrottleLimit); results are committed one by one in the main thread.
param(
    [Alias('UrlList')][string]$List = (Join-Path (Split-Path $PSScriptRoot -Parent) 'workspace/urls.txt'),
    [Alias('InputDir')][string]$SourceDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'data/source-photos'),
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'workspace/output'),
    [int]$MaxTries = 5,
    [Alias('ReferencePhotosPerImage')][int]$PhotosPerImage = 2,
    [ValidateRange(1, 4)][int]$ThrottleLimit = 1,
    [string]$Model = '',
    [string]$FeedbackFile = '',
    [string]$ApprovedImage = '',
    [string]$ReferenceMapFile = ''
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $OutputEncoding
[Console]::OutputEncoding = $OutputEncoding
if ($MaxTries -lt 1) { throw 'MaxTries must be positive.' }
if ($PhotosPerImage -lt 1) { throw 'PhotosPerImage must be positive.' }
if ($ThrottleLimit -lt 1) { throw 'ThrottleLimit must be positive.' }
foreach ($variableName in @('List', 'SourceDir', 'OutDir')) {
    Set-Variable $variableName ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Get-Variable $variableName -ValueOnly)))
}

$ProjectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'bootstrap.ps1')
$script:Config = New-WorkflowConfiguration $ProjectRoot $SourceDir $MaxTries $PhotosPerImage $Model
if($ReferenceMapFile){$script:Config.ManualReferences=Read-ManualReferenceMap $ReferenceMapFile}
if($ApprovedImage){
    if($FeedbackFile){throw 'Choose approved export or correction, not both.'}
    [void](Export-ApprovedProduct $ProjectRoot $ApprovedImage $OutDir)
    return
}
if ($FeedbackFile) {
    $FeedbackFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FeedbackFile)
    $script:Config.Feedback = Read-ImageFeedback $FeedbackFile
    $List = Join-Path $script:Config.Feedback.Folder 'retry-urls.txt'
    [IO.File]::WriteAllText($List, $script:Config.Feedback.Record.product_url + "`r`n", [Text.UTF8Encoding]::new($true))
    $ThrottleLimit = 1
    Set-ImageFeedbackStatus $FeedbackFile running
}
try {
    Invoke-BatchWorkflow $ProjectRoot $List $OutDir $ThrottleLimit $script:WorkflowModuleFiles
    if ($FeedbackFile) { Set-ImageFeedbackStatus $FeedbackFile awaiting_review $script:Batch.Dir }
} catch {
    if ($FeedbackFile) { Set-ImageFeedbackStatus $FeedbackFile failed $script:Batch.Dir $_.Exception.Message }
    throw
}
