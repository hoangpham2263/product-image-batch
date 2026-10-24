# Local only. Runs after every image/review worker has finished.
function Complete-ReviewMetadata([object[]]$Rows, [string]$NamesPath) {
    if (-not $Rows.Count) { return }
    $names = @(if (Test-Path -LiteralPath $NamesPath) {
        Get-Content -LiteralPath $NamesPath -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    })
    if (-not $names.Count) { $names = @('Alex B.', 'Jordan M.', 'Taylor R.', 'Casey L.', 'Morgan S.', 'Jamie W.') }
    $names = @($names | Get-Random -Count $names.Count)
    $now = [DateTime]::UtcNow
    $yearStart = [DateTime]::new($now.Year, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
    $maxSeconds = [long][Math]::Floor(($now - $yearStart).TotalSeconds) + 1
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        $row = $Rows[$i]
        $row.rating = if ((Get-Random -Maximum 100) -lt 60) { 5 } else { 4 }
        $row.author = $names[$i % $names.Count]
        $emailName = (($row.author.ToLowerInvariant() -replace '[^a-z0-9 ]', '').Trim() -replace ' +', '.')
        if (-not $emailName) { $emailName = 'reviewer' + ($i + 1) }
        $row.email = $emailName + '@int'
        $seconds = Get-Random -Minimum 0 -Maximum $maxSeconds
        $row.created_at = $yearStart.AddSeconds($seconds).ToString("yyyy-MM-dd HH:mm:ss 'UTC'", [Globalization.CultureInfo]::InvariantCulture)
        $row.verified_purchase = 'true'
    }
}
