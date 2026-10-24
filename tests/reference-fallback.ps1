. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$script:Config = @{ PhotosPerImage = 2; StyleExample = ''; WritingStyle = [pscustomobject]@{ scene_rules = @() } }
$script:Batch = @{ Images = $TestWorkspaceRoot }
# One verified real setting is sufficient when an optional second scene is absent.
$context = [pscustomobject]@{ product = 'apron'; presentation = 'worn'; setting = 'cafe'; source_categories = @('aprons'); details = 'black apron'; branding = 'preserve logo'; reject = 'golf' }
$script:MissingSubject = $false
function Select-Photo($Reference, $Handle, $ItemId, $Exclude, $Role, $Context, $SubjectPhoto) {
    if ($Role -eq 'Subject' -and -not $script:MissingSubject) { return 'checked-person-and-real-cafe.png' }
    throw 'No suitable source photo found after 2 checks.'
}
function Get-SourceCatalog { @{} }
$picked = @(Select-ProductReferences 'actual.png' 'apron' 'one-source' $context)
Assert ($picked.Count -eq 1 -and $picked[0] -eq 'checked-person-and-real-cafe.png') 'Optional scene failure discarded a valid real setting.'
$request = New-ProductImageRequest 'actual.png' 'one-source' $context $picked ([Collections.ArrayList]::new())
Assert ($request.Prompt -match 'Image 1 also supplies the real setting' -and $request.Prompt -match 'do not invent a different location') 'Single-reference fallback invented a new location.'
$script:MissingSubject = $true
$failed = $false
try { Select-ProductReferences 'actual.png' 'apron' 'no-source' $context | Out-Null } catch { $failed = $true }
Assert $failed 'Missing all local references must block generation.'
# Missing sample data is recorded per product and summarized for the batch.
$batchDir = Join-Path $TestWorkspaceRoot ('missing-data-test-' + [Guid]::NewGuid().ToString('N'))
$script:Batch = @{ Dir = $batchDir; MissingData = Join-Path $batchDir 'missing-data' }
$product = Join-Path $TestWorkspaceRoot 'missing-product.jpg'
[IO.File]::WriteAllBytes($product, [byte[]](1,2,3))
Save-MissingData ([pscustomobject]@{ Url = 'https://example.test/p/lamp'; Handle = 'lamp' }) '001-lamp' $context $product 'No suitable source photo found after 0 checks.'
Write-MissingDataSummary $script:Batch
Assert (Test-Path (Join-Path $batchDir 'missing-data/001-lamp/product.jpg')) 'Missing-data product image not saved.'
$row = @(Import-Csv (Join-Path $batchDir 'missing-data.csv'))
Assert ($row.Count -eq 1 -and $row[0].product_url -eq 'https://example.test/p/lamp' -and $row[0].categories -eq 'aprons') 'Missing-data summary is incomplete.'
Remove-Item -LiteralPath $batchDir, $product -Recurse -Force
Write-Host 'PASS: missing sample data is recorded; optional second scene keeps a checked real setting; zero references block.'
