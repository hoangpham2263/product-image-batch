# Checkpoint successful work before removing its URL from the queue.
function Save-ProductCheckpoint($Results, $Result, $Completed, $Item, [string]$List, [bool]$UrlDone = $true) {
    $Results.Add($Result)
    Save-Csv $Results.ToArray() $script:Batch.Csv
    if (-not $UrlDone) { return }
    $Completed.Add($Item.Url)
    Write-Lines $script:Batch.CompletedUrls $Completed.ToArray()
    Remove-FromQueue $List $Item.Url
}

function Complete-BatchExport($Results, [string]$NamesPath) {
    if (-not $Results.Count) { return }
    Write-Host ([Environment]::NewLine + '[METADATA] Assigning random review fields locally...') -ForegroundColor Cyan
    Complete-ReviewMetadata $Results.ToArray() $NamesPath
    Save-Csv $Results.ToArray() $script:Batch.Csv
}
