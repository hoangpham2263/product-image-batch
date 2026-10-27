# Verify the delivered file is a readable PNG while preserving its bytes.
function Assert-GeneratedImage([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Image technical validation failed: output image is missing.'}
    $bytes=[IO.File]::ReadAllBytes($Path)
    $info=Get-ImageSize $bytes
    if(-not $info -or $info.Format -ne 'png'){throw 'Image technical validation failed: output image cannot be read as PNG. Output must be a PNG image.'}
    $tail=[Text.Encoding]::ASCII.GetString($bytes,[Math]::Max(0,$bytes.Length-12),[Math]::Min(12,$bytes.Length))
    if($info.Width -lt 1 -or $info.Height -lt 1 -or $tail -notmatch 'IEND'){throw 'Image technical validation failed: output image cannot be read as PNG. The PNG file is incomplete.'}
}
