# Google Drive storage through the product-images-api Worker (worker/).
# workspace/drive.json (local, not in Git): { "apiUrl": "https://product-images-api....workers.dev", "adminKey": "..." }
function Get-DriveConfig([string]$WorkspaceRoot) {
    $path = Join-Path $WorkspaceRoot 'drive.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $config.apiUrl -or -not $config.adminKey) { throw "drive.json cần apiUrl và adminKey: $path" }
    return @{ ApiUrl = ([string]$config.apiUrl).TrimEnd('/'); AdminKey = [string]$config.adminKey }
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
