# Google Drive storage through the product-images-api Worker (worker/).
# workspace/drive.json (local, not in Git): { "apiUrl": "https://product-images-api....workers.dev", "adminKey": "..." }
function Get-DriveConfig([string]$WorkspaceRoot) {
    $path = Join-Path $WorkspaceRoot 'drive.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $config.apiUrl -or -not $config.adminKey) { throw "drive.json cần apiUrl và adminKey: $path" }
    return @{ ApiUrl = ([string]$config.apiUrl).TrimEnd('/'); AdminKey = [string]$config.adminKey }
}

$script:DriveApiUrl = 'https://product-images-api.hoangpham2263.workers.dev'

# Log in once per machine: the admin password is checked with the Worker, then saved only in workspace/drive.json.
function Connect-DriveAccount([string]$WorkspaceRoot, [string]$Password, [scriptblock]$Probe = {
        param($url, $key)
        try { (Invoke-WebRequest -Uri $url -Headers @{ 'x-admin-key' = $key } -UseBasicParsing -TimeoutSec 30).StatusCode }
        catch { if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 } }
    }) {
    if (-not $Password) { throw 'Nhập mật khẩu.' }
    $status = & $Probe "$script:DriveApiUrl/api/app-check" $Password
    if ($status -eq 401) { throw 'Sai mật khẩu.' }
    if ($status -ne 200) { throw "Không kết nối được máy chủ Drive ($status)." }
    New-Item -ItemType Directory -Force -Path $WorkspaceRoot | Out-Null
    $json = @{ apiUrl = $script:DriveApiUrl; adminKey = $Password } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $WorkspaceRoot 'drive.json'), $json, [Text.UTF8Encoding]::new($false))
}

function Disconnect-DriveAccount([string]$WorkspaceRoot) {
    Remove-Item -LiteralPath (Join-Path $WorkspaceRoot 'drive.json') -Force -ErrorAction SilentlyContinue
}

# Upload one PNG and return its public link for the CSV.
function Assert-DriveReady {
    $drive=$script:Config.Drive
    if(-not $drive){throw '[CAUSE:DRIVE_CONFIG] Đăng nhập Google Drive trước khi tạo ảnh để xuất link công khai.'}
    try{
        $status=Invoke-RestMethod -Uri "$($drive.ApiUrl)/api/status" -Headers @{'x-admin-key'=$drive.AdminKey} -TimeoutSec 30
        if(-not $status.connected){throw '[CAUSE:DRIVE_CONFIG] Google Drive chưa được kết nối trên máy chủ.'}
        Invoke-RestMethod -Uri "$($drive.ApiUrl)/api/app-check" -Headers @{'x-admin-key'=$drive.AdminKey} -TimeoutSec 30|Out-Null
    }catch{
        if($_.Exception.Message -match '\[CAUSE:DRIVE_CONFIG\]'){throw}
        throw '[CAUSE:DRIVE_CONFIG] Chưa kiểm tra được Drive. Đăng nhập lại hoặc kiểm tra kết nối trước khi chạy.'
    }
}

function Publish-ImageToDrive([string]$Path, [string]$BatchId, [string]$Product) {
    $drive = $script:Config.Drive
    if(-not $drive){throw '[CAUSE:DRIVE_CONFIG] Google Drive chưa được cấu hình.'}
    $query = 'batch={0}&name={1}&product={2}' -f [Uri]::EscapeDataString($BatchId), [Uri]::EscapeDataString([IO.Path]::GetFileName($Path)), [Uri]::EscapeDataString($Product)
    $bytes=[IO.File]::ReadAllBytes($Path)
    for($attempt=1;$attempt -le 3;$attempt++){
        $tag=if($script:DriveUploadIndex){"  (#$script:DriveUploadIndex)"}else{''}
        Write-Host "  [DRIVE-UPLOAD] $attempt/3$tag" -ForegroundColor Cyan
        try{
            $result=Invoke-RestMethod -Uri "$($drive.ApiUrl)/api/images?$query" -Method Post -ContentType 'image/png' -Headers @{'x-admin-key'=$drive.AdminKey} -Body $bytes -TimeoutSec 120
            $uri=$null
            if(-not [Uri]::TryCreate([string]$result.url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or -not $uri.Host){throw '[CAUSE:DRIVE_UPLOAD] Máy chủ không trả link ảnh HTTPS công khai.'}
            return [string]$result.url
        }catch{
            $code=0
            if($_.Exception.Response){try{$code=[int]$_.Exception.Response.StatusCode}catch{}}
            if($_.Exception.Message -match '\[CAUSE:DRIVE_UPLOAD\]'){throw}
            if($code -in @(401,403)){throw '[CAUSE:DRIVE_AUTH] Drive từ chối đăng nhập. Đăng nhập lại; ảnh đã tạo vẫn được giữ.'}
            if($attempt -eq 3 -or ($code -ge 400 -and $code -lt 500 -and $code -notin @(408,429))){throw "[CAUSE:DRIVE_UPLOAD] Tải ảnh lên Drive chưa thành công (HTTP $code). Ảnh đã lưu; thử bàn giao lại để tiếp tục upload, không tạo ảnh mới."}
            Write-Host "  [DRIVE-RETRY] $($attempt+1)/3 HTTP $code$tag" -ForegroundColor Cyan
            Start-Sleep -Seconds $attempt
        }
    }
}
