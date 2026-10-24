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
