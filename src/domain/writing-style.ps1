function Get-WritingStyle([string]$Path) {
    $style = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($style.schema_version -ne 1 -or -not $style.review_rules -or -not $style.scene_rules) { throw 'Invalid writing style data.' }
    return $style
}

function Get-ReviewStyleProfiles([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($data.schema_version -ne 1) { throw 'Unsupported review style schema.' }
        foreach ($profile in $data.profiles) {
            if (-not $profile.id -or -not $profile.guidance -or $profile.min_words -lt 4 -or $profile.max_words -gt 60 -or $profile.min_words -gt $profile.max_words) {
                throw 'Invalid review writing profile.'
            }
        }
        return $data.profiles
    } catch { Write-Warning 'Review style data is invalid; using the default writing style.' }
}

# Read both public-source records and the older categorized store-export format.
function Get-ReviewSamples([string]$Path, $ProductContexts, $SourceCatalog) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $categoriesById = @{}
    if ($SourceCatalog) {
        foreach ($photo in $SourceCatalog.Values) {
            if ($photo.review_id -and $photo.category) { $categoriesById[$photo.review_id] = $photo.category }
        }
    }
    $seen = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if (-not $line.Trim()) { continue }
        try { $record = $line | ConvertFrom-Json } catch { continue }
        if ($record.body -isnot [string]) { continue }
        $body = ($record.body -replace '\s+', ' ').Trim()
        $words = @($body -split '\s+').Count
        if ($words -lt 1 -or $words -gt 100 -or $body.Length -gt 1000) { continue }
        $category = $record.category
        if (-not $category -and $record.review_id) { $category = $categoriesById[$record.review_id] }
        if (-not $category -and $record.source_url) {
            foreach ($profile in $ProductContexts) {
                if ($profile.id -ne 'generic' -and $record.source_url -match $profile.pattern -and $profile.source_categories.Count) {
                    $category = $profile.source_categories[0]; break
                }
            }
        }
        if (-not $category -or $category -eq 'shop') { continue }
        $key = $category + '|' + $body.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }; $seen[$key] = $true
        [pscustomobject]@{
            category = $category; body = $body
            review_id = $record.review_id; source_url = $record.source_url; source = $record.source
            product_handle = $record.product_handle; review_no = $record.review_no
        }
    }
}

function Select-ReviewSamples($Samples, $Context) {
    $categories = @($Context.id) + @($Context.source_categories | Select-Object -First 1)
    $pool = @($Samples | Where-Object { $_.category -in $categories })
    # Use related tables only when the current category has no examples.
    $tables = @('coffee-tables', 'dining-tables', 'side-tables', 'console-tables', 'desks')
    if (-not $pool.Count -and @($categories | Where-Object { $_ -in $tables }).Count) {
        $pool += @($Samples | Where-Object { $_.category -in $tables -and $_.category -notin $categories })
    }
    if (-not $pool.Count) { return }
    # Pick once per review; repair attempts keep this same reference.
    $pool | Get-Random -Count 1
}

function Get-ReviewDraftIssue([string]$Text, $Samples) {
    if (-not $Text.Trim()) { return 'The draft was empty.' }
    if ($Text -match '[!\uFF01\u203C\u2049]') { return 'The draft used an exclamation mark. Rewrite as a plain comment without exclamatory sentences.' }
    $normalized = ([regex]::Replace($Text.ToLowerInvariant(), '[^\p{L}\p{N}]+', ' ')).Trim()
    foreach ($sample in $Samples) {
        $source = ([regex]::Replace($sample.body.ToLowerInvariant(), '[^\p{L}\p{N}]+', ' ')).Trim()
        if ($normalized -eq $source) { return 'The draft copied a reference review. Write original wording based on the attached photo.' }
        $tokens = @($source -split ' ')
        for ($i = 0; $i -le $tokens.Count - 8; $i++) {
            $phrase = $tokens[$i..($i + 7)] -join ' '
            if ((' ' + $normalized + ' ').Contains(' ' + $phrase + ' ')) {
                return 'The draft reused eight consecutive words from a reference review. Write original wording based on the attached photo.'
            }
        }
    }
    return ''
}
