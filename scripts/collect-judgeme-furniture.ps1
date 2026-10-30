<#
Thu thập ảnh review nội thất công khai từ nhiều danh mục Judge.me, kiểm tra file,
khử trùng và có thể upload vào kho Drive. Ảnh và manifest nằm trong workspace/temp,
không được commit vào Git.

Ví dụ:
  pwsh -File scripts/collect-judgeme-furniture.ps1 -Target 500
  pwsh -File scripts/collect-judgeme-furniture.ps1 -Target 500 -Upload
#>
param(
    [ValidateRange(1, 5000)]
    [int]$Target = 500,
    [string]$OutputDir = 'workspace/temp/judgeme-furniture',
    [ValidateRange(1, 24)]
    [int]$ProductsPerCategory = 10,
    [ValidateRange(1, 50)]
    [int]$PhotosPerProduct = 10,
    [ValidateRange(1, 20)]
    [int]$DownloadThreads = 8,
    [string[]]$CategoryHandles = @(),
    [bool]$KeepAllUnique = $true,
    [switch]$Upload,
    [string]$DriveConfig = 'workspace/drive.json',
    [string]$DriveGroup = 'Nội thất'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$outputRoot = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDir))
$downloadDir = Join-Path $outputRoot 'downloads'
New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

function Write-JsonFile([string]$Path, $Value, [int]$Depth = 8) {
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth $Depth), $utf8NoBom)
}

function Invoke-JsonRetry([string]$Uri, [hashtable]$Headers = @{}) {
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $Uri -Headers $Headers -TimeoutSec 45
        }
        catch {
            if ($attempt -eq 4) { throw }
            Start-Sleep -Seconds ($attempt * 2)
        }
    }
}

function ConvertTo-SafeName([string]$Value) {
    $name = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    return $name.Trim('-')
}

$defaultHandles = @(
    'beds-bed-frames', 'headboards-footboards', 'cribs-toddler-beds',
    'bedroom-furniture-sets', 'nightstands', 'dressers', 'armoires-wardrobes',
    'storage-entryway-benches', 'kitchen-dining-benches', 'vanity-benches',
    'buffets-sideboards', 'china-cabinets-hutches', 'storage-cabinets-lockers',
    'storage-chests', 'media-storage-cabinets-racks', 'entertainment-centers-tv-stands',
    'kitchen-islands', 'kitchen-dining-carts',
    'arm-chairs-recliners-sleeper-chairs', 'chaises', 'floor-chairs',
    'folding-chairs-stools', 'hanging-chairs', 'kitchen-dining-room-chairs',
    'rocking-chairs', 'slipper-chairs', 'table-bar-stools', 'office-chairs',
    'living-room-furniture-sets', 'kitchen-dining-furniture-sets', 'futons',
    'sectional-sofa-units', 'sofas', 'ottomans',
    'desks', 'workspace-tables', 'workstations-cubicles',
    'bookcases-standing-shelves', 'wall-shelves-ledges', 'room-dividers',
    'accent-tables', 'activity-tables', 'folding-tables',
    'kitchen-dining-room-tables', 'poker-game-tables', 'sewing-machine-tables',
    'outdoor-beds', 'outdoor-furniture-sets', 'outdoor-ottomans',
    'outdoor-seating', 'outdoor-storage-boxes', 'outdoor-tables'
)
$wantedHandles = if ($CategoryHandles.Count -gt 0) { $CategoryHandles } else { $defaultHandles }

Write-Host 'Đọc cây danh mục Furniture từ Judge.me...'
$allCategories = @(Invoke-JsonRetry 'https://judge.me/reviews/all_categories.json?format=json').data
$categoriesByHandle = @{}
foreach ($category in $allCategories) { $categoriesByHandle[[string]$category.handle] = $category }
$categories = @($wantedHandles | ForEach-Object { $categoriesByHandle[$_] } | Where-Object { $_ })
if ($categories.Count -eq 0) { throw 'Không tìm thấy danh mục nội thất công khai trên Judge.me.' }

$productMap = [ordered]@{}
foreach ($category in $categories) {
    $searchUri = 'https://judge.me/reviews/search.json?' + [uri]::EscapeUriString(
        "q=&page=1&sort_by=reviews_count&category_id=$($category.id)&country=VN&store_country=*&min_rating=0&min_transparency=80&min_authenticity=0&currency=VND&reviews_count=0"
    )
    try { $search = Invoke-JsonRetry $searchUri } catch { Write-Warning "Bỏ qua $($category.handle): $($_.Exception.Message)"; continue }
    $categoryProducts = @($search.data.search_results | Select-Object -First $ProductsPerCategory)
    foreach ($product in $categoryProducts) {
        if (-not $product.public_internal_api_token -or -not $product.shop_domain -or -not $product.shopify_product_id) { continue }
        $key = "$($product.shop_domain)|$($product.shopify_product_id)"
        if (-not $productMap.Contains($key)) {
            $productMap[$key] = [pscustomobject]@{
                category = [string]$category.handle
                title = [string]$product.title
                shop_domain = [string]$product.shop_domain
                api_token = [string]$product.public_internal_api_token
                external_id = [string]$product.shopify_product_id
                shop_slug = [string]$product.review_site_slug
                handle = [string]$product.handle
            }
        }
    }
    Write-Host ("  {0}: tổng {1} sản phẩm ứng viên" -f $category.handle, $productMap.Count)
}

$productGroups = @($productMap.Values | Group-Object category)
$productsRoundRobin = [Collections.Generic.List[object]]::new()
$largestGroup = ($productGroups | ForEach-Object Count | Measure-Object -Maximum).Maximum
for ($index = 0; $index -lt $largestGroup; $index++) {
    foreach ($group in $productGroups) {
        if ($index -lt $group.Count) { $productsRoundRobin.Add($group.Group[$index]) }
    }
}
$products = @($productsRoundRobin)
Write-JsonFile (Join-Path $outputRoot 'products.json') $products
Write-Host "Tìm ảnh review từ $($products.Count) sản phẩm..."

$oversampleTarget = [Math]::Ceiling($Target * 1.35)
$seenUrl = @{}
$discovered = [Collections.Generic.List[object]]::new()
foreach ($product in $products) {
    if ($discovered.Count -ge $oversampleTarget) { break }
    $base = 'https://judge.me/api/v1/widgets/product_review.json?' +
        'platform=shopify' +
        '&shop_domain=' + [uri]::EscapeDataString($product.shop_domain) +
        '&api_token=' + [uri]::EscapeDataString($product.api_token) +
        '&external_id=' + [uri]::EscapeDataString($product.external_id) +
        '&add_header_counts=true&sort_by=pictures_first&product_metrics=true&json_request=true' +
        '&per_page=10&review_type=product-reviews&review_source=all_sources&verified_only=false'
    $taken = 0
    for ($page = 1; $page -le 5 -and $taken -lt $PhotosPerProduct; $page++) {
        try { $response = Invoke-JsonRetry ($base + '&page=' + $page) @{'X-JUDGEME-REDESIGN' = 'true'} }
        catch { Write-Warning "Bỏ qua ảnh của $($product.title): $($_.Exception.Message)"; break }
        foreach ($review in @($response.reviews)) {
            foreach ($picture in @($review.pictures_urls)) {
                $url = ([string]$picture.original -split '\?')[0]
                if (-not $url -or $seenUrl.ContainsKey($url)) { continue }
                $seenUrl[$url] = $true
                $sourcePage = "https://judge.me/reviews/stores/$($product.shop_slug)/products/$($product.handle)"
                $discovered.Add([pscustomobject]@{
                    category = $product.category
                    product_title = $product.title
                    source_page = $sourcePage
                    download_url = $url
                    source_kind = 'customer-review-photo'
                    review_uuid = [string]$review.uuid
                })
                $taken++
                if ($taken -ge $PhotosPerProduct -or $discovered.Count -ge $oversampleTarget) { break }
            }
            if ($taken -ge $PhotosPerProduct -or $discovered.Count -ge $oversampleTarget) { break }
        }
        if (-not $response.total_pages -or $page -ge [int]$response.total_pages) { break }
    }
    if ($discovered.Count % 50 -lt $PhotosPerProduct) { Write-Host "  Đã tìm $($discovered.Count)/$oversampleTarget URL ảnh" }
}

Write-JsonFile (Join-Path $outputRoot 'discovered.json') @($discovered)
if ($discovered.Count -lt $Target) {
    Write-Warning "Chỉ tìm được $($discovered.Count) URL ảnh, thấp hơn mục tiêu $Target. Script vẫn tải và kiểm tra số tìm được."
}

$tasks = @()
foreach ($item in $discovered) {
    $sha1 = [Security.Cryptography.SHA1]::Create()
    try { $urlHash = [Convert]::ToHexString($sha1.ComputeHash([Text.Encoding]::UTF8.GetBytes($item.download_url))).ToLowerInvariant().Substring(0, 14) }
    finally { $sha1.Dispose() }
    $extension = [IO.Path]::GetExtension(([uri]$item.download_url).AbsolutePath).ToLowerInvariant()
    if ($extension -notin @('.jpg', '.jpeg', '.png', '.webp')) { $extension = '.jpg' }
    $fileName = 'judgeme-{0}-{1}{2}' -f (ConvertTo-SafeName $item.category), $urlHash, $extension
    $tasks += [pscustomobject]@{ item = $item; file_name = $fileName; local_path = (Join-Path $downloadDir $fileName) }
}

Write-Host "Tải và kiểm tra kỹ thuật $($tasks.Count) ảnh bằng $DownloadThreads luồng..."
$downloadResults = $tasks | ForEach-Object -Parallel {
    $task = $_
    $ErrorActionPreference = 'Stop'
    try {
        if (-not (Test-Path -LiteralPath $task.local_path)) {
            for ($attempt = 1; $attempt -le 4; $attempt++) {
                try { Invoke-WebRequest -Uri $task.item.download_url -OutFile $task.local_path -TimeoutSec 60; break }
                catch { if ($attempt -eq 4) { throw }; Start-Sleep -Seconds ($attempt * 2) }
            }
        }
        Add-Type -AssemblyName System.Drawing
        $image = [Drawing.Image]::FromFile($task.local_path)
        try {
            $width = $image.Width; $height = $image.Height; $format = $image.RawFormat.Guid.ToString()
            $thumb = [Drawing.Bitmap]::new(9, 8)
            $graphics = [Drawing.Graphics]::FromImage($thumb)
            try { $graphics.DrawImage($image, 0, 0, 9, 8) }
            finally { $graphics.Dispose() }
            $bits = [Text.StringBuilder]::new(64)
            for ($y = 0; $y -lt 8; $y++) {
                for ($x = 0; $x -lt 8; $x++) {
                    $a = $thumb.GetPixel($x, $y); $b = $thumb.GetPixel($x + 1, $y)
                    $la = 299 * $a.R + 587 * $a.G + 114 * $a.B
                    $lb = 299 * $b.R + 587 * $b.G + 114 * $b.B
                    [void]$bits.Append($(if ($la -gt $lb) { '1' } else { '0' }))
                }
            }
            $thumb.Dispose()
            $dhash = ''
            for ($i = 0; $i -lt 64; $i += 4) { $dhash += [Convert]::ToString([Convert]::ToInt32($bits.ToString($i, 4), 2), 16) }
        }
        finally { $image.Dispose() }
        $file = Get-Item -LiteralPath $task.local_path
        if ($file.Length -gt 25MB) { throw 'Ảnh vượt 25 MiB' }
        $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $task.local_path).Hash.ToLowerInvariant()
        $md5 = (Get-FileHash -Algorithm MD5 -LiteralPath $task.local_path).Hash.ToLowerInvariant()
        [pscustomobject]@{
            status = 'downloaded'
            file_name = $task.file_name
            local_path = $task.local_path
            sha256 = $sha256
            md5 = $md5
            dhash = $dhash
            bytes = $file.Length
            width = $width
            height = $height
            image_format_guid = $format
            category = $task.item.category
            product_title = $task.item.product_title
            source_page = $task.item.source_page
            download_url = $task.item.download_url
            source_kind = $task.item.source_kind
            review_uuid = $task.item.review_uuid
        }
    }
    catch {
        [pscustomobject]@{
            status = 'failed'
            file_name = $task.file_name
            local_path = $task.local_path
            category = $task.item.category
            product_title = $task.item.product_title
            source_page = $task.item.source_page
            download_url = $task.item.download_url
            source_kind = $task.item.source_kind
            review_uuid = $task.item.review_uuid
            error = $_.Exception.Message
        }
    }
} -ThrottleLimit $DownloadThreads

function Get-HammingDistance([string]$A, [string]$B) {
    $distance = 0
    for ($i = 0; $i -lt 16; $i++) {
        $xor = [Convert]::ToInt32($A.Substring($i, 1), 16) -bxor [Convert]::ToInt32($B.Substring($i, 1), 16)
        while ($xor -ne 0) { $distance += ($xor -band 1); $xor = $xor -shr 1 }
    }
    return $distance
}

$hashes = @{}
$visualHashes = [Collections.Generic.List[string]]::new()
$selected = [Collections.Generic.List[object]]::new()
foreach ($result in @($downloadResults | Where-Object status -eq 'downloaded')) {
    if ($hashes.ContainsKey($result.sha256)) { $result.status = 'duplicate'; continue }
    $hashes[$result.sha256] = $true
    $looksDuplicate = $false
    foreach ($knownVisualHash in $visualHashes) {
        if ((Get-HammingDistance $result.dhash $knownVisualHash) -le 5) { $looksDuplicate = $true; break }
    }
    if ($looksDuplicate) { $result.status = 'visual-duplicate'; continue }
    $visualHashes.Add($result.dhash)
    if ($KeepAllUnique -or $selected.Count -lt $Target) { $result.status = 'selected'; $selected.Add($result) }
    else { $result.status = 'extra' }
}
Write-JsonFile (Join-Path $outputRoot 'manifest.json') @($downloadResults)
Write-JsonFile (Join-Path $outputRoot 'selected.json') @($selected)

$failedCount = @($downloadResults | Where-Object status -eq 'failed').Count
$duplicateCount = @($downloadResults | Where-Object status -eq 'duplicate').Count
$visualDuplicateCount = @($downloadResults | Where-Object status -eq 'visual-duplicate').Count
Write-Host "Đã chọn $($selected.Count) ảnh hợp lệ kỹ thuật; lỗi $failedCount; trùng nội dung $duplicateCount; gần trùng hình $visualDuplicateCount."

if (-not $Upload) {
    Write-Host "Chưa upload. Xem manifest rồi chạy lại với -Upload để đẩy nhóm '$DriveGroup'."
    exit 0
}

if ($selected.Count -eq 0) { throw 'Không có ảnh hợp lệ để upload.' }
$drive = Get-Content -Raw -LiteralPath $DriveConfig | ConvertFrom-Json
$apiUrl = (([string]$drive.apiUrl) -replace '//(product-images-api|product-review-batch-api)\.', '//tools-hub-api.').TrimEnd('/')
if (-not $apiUrl) { throw "Thiếu apiUrl trong $DriveConfig" }

$adminKey = $env:HUB_ADMIN_KEY
if (-not $adminKey) {
    $secure = Read-Host 'Nhập mật khẩu admin (không hiện trên màn hình)' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $adminKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
if (-not $adminKey) { throw 'Chưa có mật khẩu admin.' }

$headers = @{'x-admin-key' = $adminKey}
$check = Invoke-RestMethod -Uri "$apiUrl/api/app-check" -Headers $headers -TimeoutSec 30
if ([string]$check.role -ne 'admin') { throw "Khóa không có quyền admin (role=$($check.role))." }

$groupBody = @{name = $DriveGroup} | ConvertTo-Json -Compress
try { Invoke-RestMethod -Method Post -Uri "$apiUrl/api/sources" -Headers $headers -ContentType 'application/json' -Body $groupBody -TimeoutSec 30 | Out-Null }
catch { if ($_.Exception.Response.StatusCode.value__ -ne 409) { throw } }

$groupPath = '/api/sources/' + [uri]::EscapeDataString($DriveGroup)
$remote = Invoke-RestMethod -Uri ($apiUrl + $groupPath) -Headers $headers -TimeoutSec 60
$remoteMd5 = @{}
$remoteNames = @{}
foreach ($file in @($remote.files)) { if ($file.md5) { $remoteMd5[[string]$file.md5.ToLowerInvariant()] = $true }; $remoteNames[[string]$file.name] = $true }

$uploaded = 0; $skipped = 0; $uploadFailed = 0
foreach ($item in $selected) {
    if ($remoteMd5.ContainsKey($item.md5) -or $remoteNames.ContainsKey($item.file_name)) { $skipped++; continue }
    $contentType = switch -Regex ($item.file_name) { '\.png$' {'image/png'} '\.webp$' {'image/webp'} default {'image/jpeg'} }
    try {
        Invoke-RestMethod -Method Post -Uri ($apiUrl + $groupPath + '?name=' + [uri]::EscapeDataString($item.file_name)) -Headers $headers -ContentType $contentType -InFile $item.local_path -TimeoutSec 120 | Out-Null
        $uploaded++
        if ($uploaded % 25 -eq 0) { Write-Host "  Đã upload $uploaded ảnh" }
    }
    catch { $uploadFailed++; Write-Warning "Upload lỗi $($item.file_name): $($_.Exception.Message)" }
}

$adminKey = $null
$env:HUB_ADMIN_KEY = $null
[GC]::Collect()
$uploadSummary = [pscustomobject]@{group=$DriveGroup;selected=$selected.Count;uploaded=$uploaded;skipped_existing=$skipped;failed=$uploadFailed;completed_at=(Get-Date).ToUniversalTime().ToString('o')}
Write-JsonFile (Join-Path $outputRoot 'upload-summary.json') $uploadSummary
Write-Host ("Upload xong: mới {0}, đã có {1}, lỗi {2}." -f $uploaded, $skipped, $uploadFailed)
if ($uploadFailed -gt 0) { exit 2 }
