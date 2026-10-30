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
    # A login saved with the Worker's old name moves to the new address, in the file too.
    '{"apiUrl":"https://product-images-api.hoangpham2263.workers.dev","adminKey":"k"}'|Set-Content (Join-Path $temp 'drive.json') -Encoding UTF8
    Assert ((Get-DriveConfig $temp).ApiUrl -eq 'https://tools-hub-api.hoangpham2263.workers.dev') 'The old Worker address must move to the new one.'
    Assert ((Get-Content (Join-Path $temp 'drive.json') -Raw) -match 'tools-hub-api' -and (Get-DriveConfig $temp).AdminKey -eq 'k') 'The new address must be saved, keeping the password.'
    '{"apiUrl":"https://api.test/","adminKey":"k"}'|Set-Content (Join-Path $temp 'drive.json') -Encoding UTF8

    $script:Config=@{Drive=$drive}
    $image=Join-Path $temp '001-tee.png'
    [IO.File]::WriteAllBytes($image,[byte[]](137,80,78,71))
    function Invoke-RestMethod($Uri,$Method,$ContentType,$Headers,$Body,$TimeoutSec){
        Assert ($Uri -eq 'https://api.test/api/images?batch=b%201&name=001-tee.png&product=tee' -and $Method -eq 'Post') "Unexpected upload request: $Uri"
        Assert ($Headers['x-admin-key'] -eq 'k' -and $Body.Length -eq 4) 'Admin key or image bytes missing.'
        [pscustomobject]@{url='https://api.test/img/abc.png'}
    }
    Assert ((Publish-ImageToDrive $image 'b 1' 'tee') -eq 'https://api.test/img/abc.png') 'Drive link was not returned.'
    $script:UploadCalls=0
    function Start-Sleep($Seconds,$Milliseconds) {}
    function Invoke-RestMethod {
        $script:UploadCalls++
        if($script:UploadCalls -lt 3){throw [TimeoutException]::new('Temporary upload timeout')}
        return [pscustomobject]@{url='https://api.test/img/retried.png'}
    }
    Assert ((Publish-ImageToDrive $image 'b 1' 'tee') -eq 'https://api.test/img/retried.png' -and $script:UploadCalls -eq 3) 'Transient upload retries failed.'
    function Invoke-RestMethod {return [pscustomobject]@{url='C:/local/image.png'}}
    $blocked=$false;try{Publish-ImageToDrive $image 'b 1' 'tee'|Out-Null}catch{$blocked=$_.Exception.Message -match 'DRIVE_UPLOAD'}
    Assert $blocked 'Server local paths were accepted as public links.'
    function Invoke-RestMethod {return [pscustomobject]@{connected=$false}}
    $blocked=$false;try{Assert-DriveReady}catch{$blocked=$_.Exception.Message -match 'DRIVE_CONFIG'}
    Assert $blocked 'Unconnected Drive passed startup checks.'
    $login=Join-Path $temp 'login'
    $probe={ param($url,$key) if ($key -eq 'right') { 200 } else { 401 } }
    try { Connect-DriveAccount $login 'wrong' $probe; Assert $false 'Wrong password was accepted.' } catch { Assert ($_.Exception.Message -eq 'Sai mật khẩu.') $_.Exception.Message }
    Assert (-not (Test-Path (Join-Path $login 'drive.json'))) 'drive.json written for a wrong password.'
    Connect-DriveAccount $login 'right' $probe
    Assert ((Get-DriveConfig $login).AdminKey -eq 'right') 'Login did not save drive.json.'
    Disconnect-DriveAccount $login
    Assert ($null -eq (Get-DriveConfig $login)) 'Logout did not remove drive.json.'
    Write-Host 'PASS: Drive config is optional, uploads carry the admin key and return the public link.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
