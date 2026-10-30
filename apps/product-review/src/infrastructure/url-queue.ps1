# URL queue (urls.txt). Dot-sourced by run-images.ps1.

# Parse the queue file. Returns the raw lines and the valid items (Url, Handle).
# Invalid entries are reported and left in the file.
function Read-UrlQueue([string]$Path) {
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $items = @()
    foreach ($line in $lines) {
        $value = $line.Trim()
        if (-not $value -or $value.StartsWith('#')) { continue }
        $uri = $null
        if (-not [Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https') -or -not $uri.Host) {
            Write-Warning "Invalid URL, kept in queue: $value"; continue
        }
        $handle = [Uri]::UnescapeDataString($uri.AbsolutePath.TrimEnd('/').Split('/')[-1])
        if (-not $handle -or $handle -match '[<>:"/\\|?*\x00-\x1F]' -or $handle -in @('.', '..')) {
            Write-Warning "Invalid product handle, kept in queue: $value"; continue
        }
        $items += [pscustomobject]@{ Url = $value; Handle = $handle }
    }
    [pscustomobject]@{ Lines = $lines; Items = $items }
}

# Remove the first occurrence of a finished URL (and blank lines) from the queue file.
function Remove-FromQueue([string]$Path, [string]$Url) {
    $removed = $false
    $remaining = @(foreach ($entry in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if (-not $removed -and $entry.Trim() -ceq $Url) { $removed = $true; continue }
        if ($entry.Trim()) { $entry }
    })
    Write-Lines $Path $remaining
}
