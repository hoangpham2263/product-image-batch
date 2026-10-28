# A successful HTTP response can still be Shopify's password gate, not the product.
function Test-StorefrontPasswordPage([string]$Html, [string]$FinalUrl) {
    $uri = $null
    if ([Uri]::TryCreate($FinalUrl, [UriKind]::Absolute, [ref]$uri) -and $uri.AbsolutePath.TrimEnd('/') -eq '/password') { return $true }
    if ($Html -match '(?i)data-page-type\s*=\s*["'']password["'']') { return $true }
    foreach ($tag in [regex]::Matches($Html, '(?is)<link\b[^>]*>')) {
        $attrs = @{}
        foreach ($attr in [regex]::Matches($tag.Value, '(?is)([\w:-]+)\s*=\s*["'']([^"'']*)["'']')) {
            $attrs[$attr.Groups[1].Value.ToLowerInvariant()] = [Net.WebUtility]::HtmlDecode($attr.Groups[2].Value)
        }
        if ($attrs.rel -eq 'canonical' -and $attrs.href) {
            try { $canonical = [Uri]::new([Uri]$FinalUrl, $attrs.href) } catch { continue }
            if ($canonical.AbsolutePath.TrimEnd('/') -eq '/password') { return $true }
        }
    }
    return $false
}
# Product reference image. Dot-sourced by run-images.ps1.
# Reads: $script:Batch.Refs

# Retry transient page/CDN failures without consuming an AI turn.
function Get-ProductResource([string]$Url, [string]$OutFile = '') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $request = @{ Uri = $Url; UseBasicParsing = $true; TimeoutSec = 30; ErrorAction = 'Stop' }
            if ($OutFile) { $request.OutFile = $OutFile }
            return Invoke-WebRequest @request
        } catch {
            $statusCode = 0
            if ($_.Exception.Response) {
                try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
            }
            $networkStatus = [string]$_.Exception.Status
            $timeout = $_.Exception -is [TimeoutException] -or $networkStatus -eq 'Timeout' -or $_.Exception.Message -match '(?i)timed out|timeout'
            $network = $networkStatus -in @('ConnectFailure', 'NameResolutionFailure', 'ProxyNameResolutionFailure', 'ConnectionClosed', 'ReceiveFailure', 'SendFailure', 'KeepAliveFailure')
            $transient = $timeout -or $network -or $statusCode -in @(408, 429, 500, 502, 503, 504)
            if ($transient -and $attempt -lt 3) {
                Write-Host "  [DOWNLOAD-RETRY] Attempt $($attempt + 1)/3..." -ForegroundColor Cyan
                Start-Sleep -Seconds $attempt
                continue
            }
            $cause = if ($timeout -or $statusCode -eq 408 -or $statusCode -eq 504) { 'PRODUCT_TIMEOUT' }
                elseif ($statusCode -in @(401, 403)) { 'PRODUCT_ACCESS' }
                elseif ($statusCode -eq 404) { 'PRODUCT_NOT_FOUND' }
                elseif ($transient) { 'PRODUCT_NETWORK' } else { 'PRODUCT_DOWNLOAD' }
            throw "[CAUSE:$cause] Product page/image download failed. $($_.Exception.Message)"
        }
    }
}

# Download the product page's og:image into the batch refs folder. Returns the local path.
function Get-Reference([string]$Url, [string]$ItemId) {
    $page = Get-ProductResource $Url
    $html = [string]$page.Content
    $finalUrl = if ($page.BaseResponse.ResponseUri) { [string]$page.BaseResponse.ResponseUri } elseif ($page.BaseResponse.RequestMessage.RequestUri) { [string]$page.BaseResponse.RequestMessage.RequestUri } else { $Url }
    if (Test-StorefrontPasswordPage $html $finalUrl) {
        throw '[CAUSE:STORE_LOCKED] Storefront requires a password. Make the product publicly accessible before retrying.'
    }
    $imageUrl = ''
    foreach ($tag in [regex]::Matches($html, '(?is)<meta\b[^>]*>')) {
        if ($tag.Value -match '(?i)(?:property|name)\s*=\s*["'']og:image["'']' -and $tag.Value -match '(?i)content\s*=\s*["'']([^"'']+)["'']') {
            $imageUrl = [Net.WebUtility]::HtmlDecode($Matches[1]); break
        }
    }
    if (-not $imageUrl) { throw "No product reference found: $Url" }
    $resolved = [Uri]::new([Uri]$Url, $imageUrl)
    if ($resolved.Scheme -notin @('http', 'https')) { throw 'Invalid reference image URL.' }
    $reference = Join-Path $script:Batch.Refs "$ItemId.jpg"
    Get-ProductResource $resolved.AbsoluteUri $reference | Out-Null
    return $reference
}

function Read-ProductInput($Item, [string]$ItemId) {
    Write-Host '  [PRODUCT] Loading reference...' -ForegroundColor Cyan
    $manual=@($script:Config.ManualReferences.entries|Where-Object product_url -eq $Item.Url)
    if($manual.Count -and $manual[0].product_file){
        $source=$manual[0].product_file
        if(-not (Test-Path -LiteralPath $source -PathType Leaf)){throw '[CAUSE:PRODUCT_INPUT] Ảnh sản phẩm đã gắn bị thiếu. Hãy gắn lại ảnh.'}
        $bytes=[IO.File]::ReadAllBytes($source)
        if((Get-BytesHash $bytes) -ine $manual[0].product_sha256){throw '[CAUSE:PRODUCT_INPUT] Ảnh sản phẩm đã gắn bị thay đổi. Hãy gắn lại ảnh.'}
        $size=Get-ImageSize $bytes
        if(-not $size -or $size.Width -lt 32 -or $size.Height -lt 32){throw '[CAUSE:PRODUCT_INPUT] Ảnh sản phẩm không đọc được hoặc quá nhỏ.'}
        $reference=Join-Path $script:Batch.Refs ($ItemId+'-manual-product'+[IO.Path]::GetExtension($source))
        [IO.File]::WriteAllBytes($reference,$bytes)
        Write-Host '  [PRODUCT-MANUAL] Using attached product image; no product URL request.' -ForegroundColor Cyan
    }else{
        if(([Uri]$Item.Url).Host -eq 'local.invalid'){throw '[CAUSE:PRODUCT_INPUT] Sản phẩm không có link cần được gắn ảnh sản phẩm gốc.'}
        $reference = Get-Reference $Item.Url $ItemId
    }
    [pscustomobject]@{
        Reference = $reference
        Context = Resolve-ProductContext $Item.Handle $reference $ItemId
    }
}
