. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
$tempDir = Join-Path $TestWorkspaceRoot ('product-context-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$script:Config = @{ PhotosPerImage = 2; ProductContexts = @(Get-ProductContexts (Join-Path $root 'data/product-contexts.json')); ReviewStyles = @(); StyleExample = '' }
$script:Batch = @{ Dir = $tempDir; Images = $tempDir; Logs = $tempDir; Refs = (Join-Path $tempDir "refs") }
$script:Config.SourceDir = $tempDir
$script:Config.WritingStyle = Get-WritingStyle (Join-Path $root 'data/writing-style.json')
'product' | Set-Content (Join-Path $tempDir 'actual-product.png')
'person' | Set-Content (Join-Path $tempDir 'person.png')
function Get-Reference($Url, $ItemId) { return (Join-Path $tempDir 'actual-product.png') }
function Select-Photo($Reference, $Handle, $ItemId, $Exclude, $Role, $Context, $SubjectPhoto) {
    if ($Role -eq 'Scene') {
        if ($Context.id -ne 'apron' -or $SubjectPhoto -ne (Join-Path $tempDir 'person.png')) { throw 'Scene was not evaluated with the selected person and product.' }
        throw 'No suitable source photo found after 2 checks.'
    }
    return (Join-Path $tempDir 'person.png')
}
function Invoke-AI($PromptText, $Images, $ResultFile, $Sandbox) {
    if ($ResultFile -like '*-context.txt') {
        return '{"category_key":"apron","existing_profile":"apron","product":"bib apron","presentation":"worn","setting":"cafe","details":"Black bib, neck strap and front pockets","reject":"decorative gate","search_query":"apron cafe real photos"}'
    }
    if ($ResultFile -like '*-quality-*.txt') {
        $script:QualityCalls++
        if ($script:AlwaysFail -or $script:QualityCalls -eq 1) { return 'FAIL: apron at a decorative gate with golf branding' }
        return 'PASS'
    }
    if ($ResultFile -like '*-review.txt') {
        if ($PromptText -notmatch 'reviewed product is: bib apron' -or $PromptText -notmatch 'not the white T-shirt underneath') { throw 'Review is not focused on the apron.' }
        return 'I like the black bib and the simple front pockets.'
    }
    $script:ImageCalls++
    if ($PromptText -notmatch 'Scene guidance: Show one ordinary moment') { throw 'Missing natural scene guidance.' }
    if ($Images.Count -ne 2 -or $PromptText -notmatch 'Image 1 also supplies the real setting' -or $PromptText -notmatch 'Image 2 is the PRODUCT reference') { throw 'Scene fallback changed reference roles incorrectly.' }
    if ($PromptText -notmatch 'Never add GOLF' -or $PromptText -notmatch 'cafe service counter') { throw 'Apron context rules were not included.' }
    if ($script:ImageCalls -eq 2 -and $PromptText -notmatch 'previous result failed inspection') { throw 'Rejected scene was not corrected.' }
    if ($PromptText -notmatch '(?m)^Save a new PNG at this exact path: (.+)$') { throw 'Missing output path.' }
    'image' | Set-Content -LiteralPath $Matches[1].Trim()
    return 'BRAND: Cedar Kitchen'
}
try {
    if ((Get-ProductContext 'custom-bib-apron').id -ne 'apron' -or (Get-ProductContext 'bulk-polo-shirt').id -ne 'polo' -or (Get-ProductContext 'golf-polo').id -ne 'golf') { throw 'Incorrect product classification.' }
    $item = [pscustomobject]@{ Handle = 'custom-bib-apron'; Url = 'https://example.test/apron' }
    $brands = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
    $script:QualityCalls = 0; $script:ImageCalls = 0; $script:AlwaysFail = $false
    $result = Invoke-ProductItem $item '001-apron' $brands
    if ($script:ImageCalls -ne 2 -or $script:QualityCalls -ne 2 -or $result.body -notmatch 'front pockets') { throw 'Quality repair or product review failed.' }
    if (-not (Test-Path (Join-Path $tempDir 'rejected/001-apron-attempt-1.png'))) { throw 'Rejected image evidence was lost.' }
    $script:QualityCalls = 0; $script:ImageCalls = 0; $script:AlwaysFail = $true; $blocked = $false
    try { Invoke-ProductItem $item '002-apron' $brands | Out-Null } catch {
        if ($_.Exception.Message -notlike 'Image quality check failed:*') { throw }
        $blocked = $true
    }
    if (-not $blocked -or $script:ImageCalls -ne 2) { throw 'Bad images must stop after one repair and must not be exported.' }
    Write-Host 'PASS: product contexts, joint scene checks, contextual fallback, bounded quality repair and apron-focused reviews.' -ForegroundColor Green
} finally {
    $resolved = [IO.Path]::GetFullPath($tempDir)
    $allowed = [IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\') + '\'
    if ($resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'product-context-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
