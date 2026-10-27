. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
. (Join-Path $project 'src/bootstrap.ps1')
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('drive-storage-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try{
    Assert ($null -eq (Get-DriveConfig $temp)) 'Missing drive.json must leave Drive off.'
    '{"apiUrl":"https://api.test/","adminKey":"k"}'|Set-Content (Join-Path $temp 'drive.json') -Encoding UTF8
    $drive=Get-DriveConfig $temp
    Assert ($drive.ApiUrl -eq 'https://api.test' -and $drive.AdminKey -eq 'k') 'drive.json was not read.'

    $script:Config=@{Drive=$drive}
    $image=Join-Path $temp '001-tee.png'
    [IO.File]::WriteAllBytes($image,[byte[]](137,80,78,71))
    function Invoke-RestMethod($Uri,$Method,$ContentType,$Headers,$Body,$TimeoutSec){
        Assert ($Uri -eq 'https://api.test/api/images?batch=b%201&name=001-tee.png&product=tee' -and $Method -eq 'Post') "Unexpected upload request: $Uri"
        Assert ($Headers['x-admin-key'] -eq 'k' -and $Body.Length -eq 4) 'Admin key or image bytes missing.'
        [pscustomobject]@{url='https://api.test/img/abc.png'}
    }
    Assert ((Publish-ImageToDrive $image 'b 1' 'tee') -eq 'https://api.test/img/abc.png') 'Drive link was not returned.'
    Write-Host 'PASS: Drive config is optional, uploads carry the admin key and return the public link.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
