function New-Batch([string]$OutDir) {
    $localTime = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'SE Asia Standard Time')
    $id = $localTime.ToString('yyyy-MM-dd_HH-mm-ss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
    $dir = Join-Path $OutDir $id
    $batch = @{
        Id      = $id
        Dir     = $dir
        InputUrls = Join-Path $dir 'urls.input.txt'
        CompletedUrls = Join-Path $dir 'urls.completed.txt'
        Images  = Join-Path $dir 'images'
        Logs    = Join-Path $dir 'logs'
        Refs    = Join-Path $dir 'refs'
        Csv     = Join-Path $dir 'loox_import.csv'
        MissingData = Join-Path $dir 'missing-data'
    }
    # URL history belongs to the output batch; source photos remain reusable.
    New-Item -ItemType Directory -Force $batch.Images, $batch.Logs, $batch.Refs | Out-Null
    return $batch
}
