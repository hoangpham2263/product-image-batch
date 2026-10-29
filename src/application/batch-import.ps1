# Nhập hàng loạt: many products at once from one table (docs/import.md). Each row is one product image of a link with
# its review images; several rows with the same link give that link several product images. Plain links, one per
# line, still work and only add the links. Images are downloaded and attached exactly as if picked by hand.
$script:ImportColumns = @('product_url', 'product_image', 'review_images')

# Rows of the table, or the problems found in it (with line numbers) so nothing is half imported by mistake.
function ConvertFrom-ProductBatch([string]$Text) {
    $lines = @($Text -replace '^﻿', '' -split '\r?\n' | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
    if (-not $lines.Count) { return @{ Rows = @(); Errors = @('Chưa có dòng nào.') } }
    $header = $lines[0].Trim()
    $errors = [Collections.Generic.List[string]]::new()
    $rows = [Collections.Generic.List[object]]::new()
    if ($header -notmatch 'product_url') {
        # Plain links: one per line, nothing to download.
        for ($i = 0; $i -lt $lines.Count; $i++) { $rows.Add([pscustomobject]@{ Line = $i + 1; Url = $lines[$i].Trim(); Product = ''; Reviews = @() }) }
    } else {
        $delimiter = if ($header.Contains("`t")) { "`t" } else { ',' }
        $names = @($header -split [regex]::Escape($delimiter) | ForEach-Object { $_.Trim().Trim('"').ToLowerInvariant() })
        foreach ($name in $names) { if ($name -and $name -notin $script:ImportColumns) { $errors.Add("Dòng 1: cột lạ '$name'. Chỉ dùng: $($script:ImportColumns -join ', ').") } }
        $records = @($lines | ConvertFrom-Csv -Delimiter $delimiter)
        for ($i = 0; $i -lt $records.Count; $i++) {
            $r = $records[$i]
            $get = { param($n) $p = $r.PSObject.Properties | Where-Object { $_.Name.Trim().ToLowerInvariant() -eq $n } | Select-Object -First 1; if ($p) { ([string]$p.Value).Trim() } else { '' } }
            $reviews = @((& $get 'review_images') -split '[|\r\n]|,\s*(?=https?://)' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $rows.Add([pscustomobject]@{ Line = $i + 2; Url = (& $get 'product_url'); Product = (& $get 'product_image'); Reviews = $reviews })
        }
    }
    foreach ($row in $rows) {
        if (-not (Test-ImportLink $row.Url)) { $errors.Add("Dòng $($row.Line): link sản phẩm không hợp lệ '$($row.Url)'.") }
        foreach ($image in @(@($row.Product) + @($row.Reviews) | Where-Object { $_ })) {
            if (-not (Test-ImportLink $image) -and -not (Test-Path -LiteralPath $image -PathType Leaf)) { $errors.Add("Dòng $($row.Line): ảnh không phải link http(s) hay file trên máy '$image'.") }
        }
    }
    return @{ Rows = $rows.ToArray(); Errors = $errors.ToArray() }
}

function Test-ImportLink([string]$Value) {
    $uri = $null
    return [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @('http', 'https')
}

# An image from a link or a file on this machine, as a JPEG/PNG file in $Folder (the app attaches only these).
function Get-ImportImage([string]$Source, [string]$Folder) {
    $path = Join-Path $Folder ([Guid]::NewGuid().ToString('N'))
    if (Test-ImportLink $Source) {
        try { Invoke-WebRequest -Uri $Source -OutFile $path -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent' = 'product-review-batch' } | Out-Null }
        catch {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
            throw $(if ($code) { "không tải được ảnh (mã $code)" } else { 'không tải được ảnh (mạng hoặc link)' })
        }
    } else { Copy-Item -LiteralPath $Source -Destination $path }
    $size = (Get-Item -LiteralPath $path).Length
    $head = [byte[]]::new(8)
    $stream = [IO.File]::OpenRead($path); try { [void]$stream.Read($head, 0, 8) } finally { $stream.Dispose() }
    $extension = if ($head[0] -eq 0xFF -and $head[1] -eq 0xD8) { '.jpg' } elseif ($head[0] -eq 0x89 -and $head[1] -eq 0x50 -and $head[2] -eq 0x4E -and $head[3] -eq 0x47) { '.png' } else { '' }
    if (-not $extension -or $size -gt 25MB) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        throw $(if ($size -gt 25MB) { 'ảnh quá 25 MB' } else { 'không phải ảnh JPG hoặc PNG' })
    }
    Rename-Item -LiteralPath $path -NewName ([IO.Path]::GetFileName($path) + $extension)
    return $path + $extension
}

# Attaches every row's images to its link. $OnProgress gets (images done, images in all). A row whose product image
# fails keeps none of its reviews, so a review never lands on another product image.
function Import-ProductBatch([string]$ProjectRoot, $Rows, [scriptblock]$OnProgress) {
    $temp = Join-Path $ProjectRoot ('workspace/temp/import-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $mapPath = Join-Path $ProjectRoot 'workspace/reference-inputs/references.json'
    $total = [int](@($Rows | ForEach-Object { @(@($_.Product) + @($_.Reviews) | Where-Object { $_ }).Count }) | Measure-Object -Sum).Sum
    $result = [ordered]@{ links = @(); products = 0; reviews = 0; failed = @() }
    $done = 0
    $step = { if ($OnProgress) { & $OnProgress $done $total } }
    try {
        foreach ($row in $Rows) {
            if ($row.Url -notin $result.links) { $result.links += $row.Url }
            $target = -1
            if ($row.Product) {
                try {
                    $file = Get-ImportImage $row.Product $temp
                    [void](Save-ManualReference $ProjectRoot $row.Url $file Product)
                    $hash = Get-BytesHash ([IO.File]::ReadAllBytes($file))
                    $saved = @(Get-ManualProducts @((Read-ManualReferenceMap $mapPath).entries | Where-Object product_url -eq $row.Url)[0])
                    for ($i = 0; $i -lt $saved.Count; $i++) { if ($saved[$i].sha256 -eq $hash) { $target = $i } }
                    $result.products++
                } catch {
                    $result.failed += [ordered]@{ line = $row.Line; image = $row.Product; reason = "ảnh sản phẩm: $($_.Exception.Message)" }
                    $done += 1 + @($row.Reviews).Count; & $step
                    continue
                }
                $done++; & $step
            }
            foreach ($review in @($row.Reviews)) {
                try {
                    [void](Save-ManualReference $ProjectRoot $row.Url (Get-ImportImage $review $temp) Scene $target)
                    $result.reviews++
                } catch { $result.failed += [ordered]@{ line = $row.Line; image = $review; reason = $_.Exception.Message } }
                $done++; & $step
            }
        }
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    return $result
}
