. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('batch-review-'+[Guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path (Join-Path $temp 'images') -Force|Out-Null
    $rows=@(foreach($n in 1..3){
        $image=Join-Path $temp "images/00$n-tee.png";New-TestPng $image 1 1 ([byte[]](10,0,0))
        [pscustomobject]@{product_handle="tee$n";rating='5';author='A';email='';body="b$n";created_at='2026-10-28';verified_purchase='true';photo_url="https://x.test/img/$n.png";photo_path=($image -replace '\\','/')}
    })
    Save-BatchResults $rows $temp
    $items=@(Get-BatchReview $temp)
    Assert ($items.Count -eq 3 -and -not $items[0].Decision) 'Every result must be listed, undecided.'
    Set-BatchReviewDecision $temp '001-tee' ok
    Set-BatchReviewDecision $temp '002-tee' bad
    $failed=$false;try{Export-ReviewedCsv $temp|Out-Null}catch{$failed=$_.Exception.Message -match 'chưa duyệt'}
    Assert $failed 'The final file must wait until every image is checked.'
    Set-BatchReviewDecision $temp '003-tee' ok
    Set-BatchReviewDecision $temp '003-tee' ''
    Assert (-not @(Get-BatchReview $temp)[2].Decision) 'Clicking a decision again must clear it.'
    Set-BatchReviewDecision $temp '003-tee' ok
    $csv=@(Import-Csv (Export-ReviewedCsv $temp))
    Assert ($csv.Count -eq 2 -and ($csv.product_handle -join ',') -eq 'tee1,tee3') 'Only images marked ok go into the final CSV.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'PASS: every result is checked before the final CSV, which keeps only accepted images.'
