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
    $status = & $Probe "$script:DriveApiUrl/api/images" $Password
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
function Publish-ImageToDrive([string]$Path, [string]$BatchId, [string]$Product) {
    $drive = $script:Config.Drive
    $query = 'batch={0}&name={1}&product={2}' -f [Uri]::EscapeDataString($BatchId), [Uri]::EscapeDataString([IO.Path]::GetFileName($Path)), [Uri]::EscapeDataString($Product)
    $result = Invoke-RestMethod -Uri "$($drive.ApiUrl)/api/images?$query" -Method Post -ContentType 'image/png' `
        -Headers @{ 'x-admin-key' = $drive.AdminKey } -Body ([IO.File]::ReadAllBytes($Path)) -TimeoutSec 120
    if (-not $result.url) { throw 'Drive không trả link ảnh.' }
    return [string]$result.url
}
