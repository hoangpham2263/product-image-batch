# Local sample library: content hashes and catalog entries.
function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

# The catalog is the single index of local sample photos and their categories.
function Get-SampleCatalogEntries([string]$SourceDir) {
    $path = Join-Path $SourceDir 'catalog.json'
    if (-not (Test-Path -LiteralPath $path)) { return }
    $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($data.schema_version -ne 1) { throw "Invalid source catalog: $path" }
    foreach ($entry in $data.photos) { $entry | Add-Member NoteProperty _root $SourceDir -Force; $entry }
}
