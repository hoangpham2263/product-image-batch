function Set-FeedbackPreview($Picture, [string]$Path) {
    if ($Picture.Image) { $Picture.Image.Dispose(); $Picture.Image=$null }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $stream = [IO.File]::OpenRead($Path)
    try { $loaded = [Drawing.Image]::FromStream($stream); try { $Picture.Image = [Drawing.Bitmap]::new($loaded) } finally { $loaded.Dispose() } } finally { $stream.Dispose() }
}
