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
    [string]$ReferenceMapFile = '',
    [switch]$LocalOnly,
    # codex: Codex CLI; chatgpt / flow: the signed-in browser tab through bridge/ + extension/.
    [ValidateSet('codex', 'chatgpt', 'flow')][string]$ImageBackend = $(if ($env:PIB_IMAGE_BACKEND) { $env:PIB_IMAGE_BACKEND } else { 'codex' })
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
# Library photos live on Drive: refresh the chosen group before the catalog is read.
if (-not $LocalOnly -and $ReferenceMapFile -and (Test-Path -LiteralPath $ReferenceMapFile)) {
    $referenceMap = Read-ManualReferenceMap $ReferenceMapFile
    $sourceDrive = Get-DriveConfig (Join-Path $ProjectRoot 'workspace')
    if ($referenceMap.allow_library_fallback -and $referenceMap.source_library -eq 'local') { Write-Host '  [SOURCE] Dùng kho ảnh trên máy.' -ForegroundColor Cyan }
    elseif ($referenceMap.allow_library_fallback -and $sourceDrive) {
        try {
            $sync = Sync-SourceGroup $sourceDrive $SourceDir $referenceMap.preferred_source_group
            Write-Host "  [SOURCE] $($sync.Group): $($sync.Total) ảnh, tải mới $($sync.Downloaded)." -ForegroundColor Cyan
        } catch { Write-Warning "Chưa tải được kho ảnh $($referenceMap.preferred_source_group) từ Drive; dùng ảnh đã có trên máy. $($_.Exception.Message)" }
    }
}
$script:Config = New-WorkflowConfiguration $ProjectRoot $SourceDir $MaxTries $PhotosPerImage $Model
$script:Config.DriveRequired = -not $LocalOnly
if($LocalOnly){$script:Config.Drive=$null}
if($script:Config.DriveRequired){
    try{Assert-DriveReady}
    catch{Write-Warning ("Failed; "+$_.Exception.Message);throw}
}
$script:Config.ImageBackend = $ImageBackend
if ($ImageBackend -ne 'codex') { Start-ImageBridge $ProjectRoot }
if($ReferenceMapFile){$script:Config.ManualReferences=Read-ManualReferenceMap $ReferenceMapFile}
try {
    Invoke-BatchWorkflow $ProjectRoot $List $OutDir $ThrottleLimit $script:WorkflowModuleFiles
} catch {
    throw
}
