. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('multi-scene-'+[Guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $temp -Force|Out-Null
    $a=Join-Path $temp 'a.png';New-TestPng $a 1 1 ([byte[]](10,0,0))
    $b=Join-Path $temp 'b.png';New-TestPng $b 1 1 ([byte[]](0,10,0))
    $url='https://shop.example/products/tee';$other='https://shop.example/products/cap'
    $path=Save-ManualReference $temp $url $a
    [void](Save-ManualReference $temp $url $b)
    [void](Save-ManualReference $temp $url $b)
    [void](Save-ManualReference $temp $other $a)
    $map=Read-ManualReferenceMap $path
    $scenes=@(Get-ManualScenes @($map.entries|Where-Object product_url -eq $url)[0])
    Assert ($scenes.Count -eq 2) 'Several scene images on one link must be kept, duplicates once.'
    Assert (@($map.entries|Where-Object product_url -eq $url)[0].file -eq $scenes[0].file) 'file must mirror the first scene for older readers.'

    $script:Config=@{ManualReferences=$map}
    $jobs=@(Expand-SceneJobs @([pscustomobject]@{Url=$url;Handle='tee'},[pscustomobject]@{Url=$other;Handle='cap'}))
    Assert ($jobs.Count -eq 3 -and $jobs[0].Scene.sha256 -ne $jobs[1].Scene.sha256 -and -not $jobs[2].PSObject.Properties['Scene']) 'Each scene image must become its own job.'

    $legacy=Join-Path $temp 'legacy.json'
    '{"schema_version":1,"allow_library_fallback":false,"entries":[{"product_url":"https://shop.example/products/old","file":"x.png","sha256":"'+('a'*64)+'"}]}'|Set-Content $legacy -Encoding UTF8
    Assert (@(Get-ManualScenes (Read-ManualReferenceMap $legacy).entries[0]).Count -eq 1) 'Maps saved before multi-image support must still load.'

    Remove-ManualScene $path $url 0
    $left=@(Get-ManualScenes @((Read-ManualReferenceMap $path).entries|Where-Object product_url -eq $url)[0])
    Assert ($left.Count -eq 1 -and $left[0].sha256 -eq $scenes[1].sha256) 'Removing one image must keep the others.'
    Remove-ManualScene $path $url 0
    Assert (-not @((Read-ManualReferenceMap $path).entries|Where-Object product_url -eq $url).Count) 'A link with no images left must drop its entry.'

    $results=[Collections.Generic.List[object]]::new();$completed=[Collections.Generic.List[string]]::new()
    $list=Join-Path $temp 'urls.txt';[IO.File]::WriteAllLines($list,[string[]]@($url))
    $script:Batch=@{Csv=(Join-Path $temp 'out.csv');CompletedUrls=(Join-Path $temp 'done.txt')}
    function Save-Csv{}
    Save-ProductCheckpoint $results ([pscustomobject]@{photo_path='a'}) $completed $jobs[0] $list $false
    Assert ((Get-Content $list) -contains $url) 'A link must stay queued until all its images are done.'
    Save-ProductCheckpoint $results ([pscustomobject]@{photo_path='b'}) $completed $jobs[1] $list $true
    Assert (-not ((Get-Content $list) -contains $url)) 'A link must leave the queue after its last image.'
    Write-Host 'PASS: several scene images per link, one job each, legacy maps, per-image removal and queue checkpoint.' -ForegroundColor Green
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
