. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$temp = Join-Path $TestWorkspaceRoot ('scene-selection-' + [Guid]::NewGuid().ToString('N'))
try {
    $source = Join-Path $temp 'dining-tables'
    New-Item -ItemType Directory -Path $source -Force | Out-Null
    foreach ($n in 1..3) { 'fixture' | Set-Content (Join-Path $source "$n.jpg") }
    $script:Config = @{SourceDir=$temp;MaxTries=3}
    $script:Batch = @{Logs=$temp}
    $context = [pscustomobject]@{product='Dining table with 12 chairs';presentation='placed';setting='spacious dining room';source_categories=@('dining-tables');reject='implausible scale'}
    $script:Checks=0
    function Invoke-AI($PromptText, $Images, $ResultFile) {
        Assert ($PromptText -match 'chair count alone are not rejection reasons' -and $PromptText -match 'adequate visible space') 'Room compatibility must be checked independently of reference furniture design.'
        Assert ($PromptText -match 'NOFIT: followed by one short concrete reason') 'Missing rejection diagnosis.'
        $script:Checks++
        if ($script:Checks -lt 3) { return 'NOFIT: room is too cramped for the complete set' }
        return 'FIT'
    }
    $chosen = Select-Photo 'product.jpg' 'table' '001-table' @() Scene $context
    Assert ($script:Checks -eq 3 -and (Test-Path $chosen)) 'Object scene search stopped after only two candidates.'
    $evidence=Get-Content (Join-Path $temp '001-table-fit-1.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($evidence.photo -like '*.jpg' -and $evidence.verdict -match 'too cramped') 'Rejected photo and reason were not retained.'
    # A previously used editorial image must not outrank every unused review scene.
    $history = Join-Path $temp 'output/previous/refs/001'
    New-Item -ItemType Directory -Path $history -Force | Out-Null
    $usedPhoto = Join-Path $source '1.jpg'
    @{images=@(@{role='scene';original_path=$usedPhoto})} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $history 'manifest.json')
    $script:Batch.Dir = Join-Path $temp 'output/current'
    function Get-SourceCatalog {
        $result = @{}
        foreach ($n in 1..3) {
            $result[(Join-Path $source "$n.jpg")] = [pscustomobject]@{category='dining-tables';source_kind=$(if($n -eq 1){'editorial'}else{'review'})}
        }
        return $result
    }
    function Invoke-AI($PromptText, $Images, $ResultFile) {
        Assert ($PromptText -match 'compatible camera angle' -and $PromptText -match 'low-resolution' -and $PromptText -match 'If uncertain, return NOFIT') 'Scene suitability must include insertion angle, quality and uncertainty.'
        return 'FIT'
    }
    $rotated = Select-Photo 'product.jpg' 'table' '002-table' @() Scene $context
    Assert ($rotated -ne $usedPhoto) 'Previously used editorial room monopolized selection despite unused alternatives.'
    $historyUse = Get-ReferenceLastUse
    Assert ($historyUse.ContainsKey($usedPhoto)) 'Reference history must survive across batches.'
    $actualProduct = Join-Path $temp 'actual-product.bin'
    [IO.File]::WriteAllText($actualProduct, 'actual product fixture')
    $script:ProductHash = Get-BytesHash ([IO.File]::ReadAllBytes($actualProduct))
    $script:Config.ActiveProductUrl='https://example.test/p/twelve-chair-set'
    function Get-SourceCatalog {
        $result = @{}
        foreach ($n in 1..3) {
            $verdict = if ($n -eq 1) { 'FIT' } else { 'NOFIT' }
            $checks = if ($n -lt 3) { @([pscustomobject]@{product_sha256=$script:ProductHash;product_url='https://example.test/p/twelve-chair-set';verdict=$verdict}) } else { @() }
            $result[(Join-Path $source "$n.jpg")] = [pscustomobject]@{category='dining-tables';source_kind='customer_gallery';fit_checks=$checks}
        }
        return $result
    }
    $fitFirst = Select-Photo $actualProduct 'table' '003-table' @() Scene $context
    Assert ($fitFirst -eq $usedPhoto) 'Known product compatibility must outrank unused but untested rooms.'
    $unknown = Select-Photo $actualProduct 'table' '004-table' @($usedPhoto) Scene $context
    Assert ($unknown -eq (Join-Path $source '3.jpg')) 'A rejected room for identical product bytes must be excluded.'
    $script:Config.ActiveProductUrl='https://example.test/p/table-only-2m8'
    $samePhotoOtherListing=Select-Photo $actualProduct 'table-only' 'same-photo-other-listing' @($usedPhoto,(Join-Path $source '3.jpg')) Scene $context
    Assert ($samePhotoOtherListing -eq (Join-Path $source '2.jpg')) 'Fit evidence leaked across different listings that reuse the exact same photograph.'
    $script:Config.ActiveProductUrl='https://example.test/p/twelve-chair-set'
    [IO.File]::WriteAllText($actualProduct, 'different product fixture')
    $different = Select-Photo $actualProduct 'table' '005-table' @($usedPhoto,(Join-Path $source '3.jpg')) Scene $context
    Assert ($different -eq (Join-Path $source '2.jpg')) 'Compatibility evidence must not leak to a different product.'
    Write-Host 'PASS: object scenes use configured search budget; room capacity, source design and rejection evidence.' -ForegroundColor Green
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    $allowed=[IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\')+'\'
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'scene-selection-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
