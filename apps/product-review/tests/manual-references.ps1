. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
Add-Type -AssemblyName System.Drawing
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('manual-ref-'+[Guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $temp -Force|Out-Null
    $original=Join-Path $temp 'room.png';$bitmap=[Drawing.Bitmap]::new(64,48)
    try{$g=[Drawing.Graphics]::FromImage($bitmap);$g.Clear([Drawing.Color]::Tan);$g.Dispose();$bitmap.Save($original,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    $url='https://example.test/p/table';$otherUrl='https://example.test/p/other'
    $mapPath=Save-ManualReference $temp $url $original
    [void](Save-ManualReference $temp $otherUrl $original)
    $map=Read-ManualReferenceMap $mapPath
    Assert ($map.entries.Count -eq 2) 'Mappings lost.'
    $first=@($map.entries|Where-Object product_url -eq $url)[0]
    [IO.File]::WriteAllText($original,'source changed after attachment')
    Assert ((Get-BytesHash ([IO.File]::ReadAllBytes($first.file))) -eq $first.sha256) 'Attached image did not retain independent bytes.'
    $script:Config=@{ActiveProductUrl=$url;ManualReferences=[Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($map));PhotosPerImage=1}
    $script:Batch=@{Logs=$temp}
    $context=[pscustomobject]@{product='table';presentation='placed';source_categories=@('dining-tables')}
    $script:Verdict='FIT';$script:LibraryCalls=0
    function Test-ReferencePhoto($Photo,$Reference,$Context,$Role){Assert ($Photo -eq $first.file -and $Role -eq 'Scene') 'Wrong link image or role.';return $script:Verdict}
    function Select-Photo{$script:LibraryCalls++;return 'library-fallback.jpg'}
    $picked=@(Select-ProductReferences 'product.jpg' 'table' 'manual' $context)
    Assert ($picked.Count -eq 1 -and $picked[0] -eq $first.file -and $script:LibraryCalls -eq 0) 'Manual reference did not bypass random library selection.'
    function Test-ReferencePhoto {throw 'Manually attached photos must not trigger AI suitability QA.'}
    Assert ((Select-ProductReferences 'product.jpg' 'table' 'manual-no-qa' $context) -eq $first.file) 'User-selected photo was not used directly.'
    $script:Config.ActiveProductUrl='https://example.test/p/unattached'
    $rejected=$false;try{Select-ProductReferences 'product.jpg' 'table' 'missing-manual' $context|Out-Null}catch{$rejected=$true}
    Assert ($rejected -and $script:LibraryCalls -eq 0) 'A product image without a review must stop, never pick from the library.'
    [IO.File]::WriteAllText($first.file,'tampered snapshot');$script:Config.ActiveProductUrl=$url
    $rejected=$false;try{Select-ProductReferences 'product.jpg' 'table' 'changed-manual' $context|Out-Null}catch{$rejected=$true}
    Assert $rejected 'Changed manual snapshot was used without verification.'
    Write-Host 'PASS: per-URL image snapshots, serialized worker inputs, strict explicit selection, and rejection without substitution.' -ForegroundColor Green
}finally{
    $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\')+'\'
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'manual-ref-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
