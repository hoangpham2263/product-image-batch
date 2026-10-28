. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('manual-product-'+[Guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $temp -Force|Out-Null
    $photo=Join-Path $temp 'product.png';New-TestPng $photo 1 1 ([byte[]](0,0,128))
    $url='https://private.example/products/draft-shirt'
    $path=Save-ManualReference $temp $url $photo Product
    $map=Read-ManualReferenceMap $path
    Assert ($map.entries.Count -eq 1 -and $map.entries[0].product_file -and -not $map.entries[0].file) 'Product-only mapping was rejected.'
    [void](Save-ManualReference $temp $url $photo)
    $script:Config=@{ManualReferences=(Read-ManualReferenceMap $path);ActiveProductUrl=$url;SourceDir=$temp}
    $script:Batch=@{Refs=$temp;Logs=$temp}
    function Get-Reference {throw 'Unexpected network access for attached product.'}
    function Resolve-ProductContext($Handle,$Reference,$ItemId){
        Assert ((Get-BytesHash ([IO.File]::ReadAllBytes($Reference))) -eq $script:Config.ManualReferences.entries[0].product_sha256) 'Classification received the wrong image.'
        return [pscustomobject]@{presentation='worn'}
    }
    $item=[pscustomobject]@{Url=$url;Handle='draft-shirt'}
    $product=Read-ProductInput $item '001-draft'
    Assert ((Test-Path $product.Reference) -and $product.Reference -ne $photo) 'Manual product was not snapshotted.'
    $scene=@(Select-ProductReferences $product.Reference $item.Handle '001-draft' $product.Context)
    Assert ($scene.Count -eq 1 -and $scene[0] -eq $script:Config.ManualReferences.entries[0].file) 'Product and scene roles were confused.'
    $request=[pscustomobject]@{Images=@($scene[0],$product.Reference);Output=(Join-Path $temp 'out.png');SceneBase=''}
    $bundle=Save-ProductReferenceBundle $item '001-archive' $product.Context $request 1
    $manifest=Get-Content (Join-Path $bundle.Folder 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($manifest.images[1].source_kind -eq 'user_product' -and $manifest.images[1].sha256 -eq $script:Config.ManualReferences.entries[0].product_sha256) 'Manual product provenance or snapshot hash was lost.'
    $saved=$script:Config.ManualReferences.entries[0].product_file
    [IO.File]::WriteAllText($saved,'changed')
    $blocked=$false;try{Read-ProductInput $item '002-draft'|Out-Null}catch{$blocked=$_.Exception.Message -match 'PRODUCT_INPUT'}
    Assert $blocked 'Changed product input fell back to the website or AI.'
    Write-Host 'PASS: private product uses local image without HTTP; separate scene, snapshot and hash enforcement.'
}finally{
    $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\')+'\'
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'manual-product-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
