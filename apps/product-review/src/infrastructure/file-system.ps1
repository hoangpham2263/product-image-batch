# Shared helpers. Dot-sourced by run-images.ps1.

# Write lines atomically (temp file, then replace). UTF-8 with BOM.
function Write-Lines([string]$Path, [string[]]$Lines) {
    $temp = "$Path.tmp"
    [IO.File]::WriteAllLines($temp, [string[]]@($Lines), [Text.UTF8Encoding]::new($true))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
