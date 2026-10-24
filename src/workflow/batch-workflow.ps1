# Queue locking, runspace lifecycle and batch coordination.
function Invoke-BatchWorkflow([string]$ProjectRoot, [string]$List, [string]$OutDir, [int]$ThrottleLimit, [string[]]$ModuleFiles) {
    $script:Batch = @{}
    # Workers get independent objects; context enrichment must not mutate shared samples.
    $configSnapshot = [Management.Automation.PSSerializer]::Serialize($script:Config, 20)
    # Worker body, run in its own runspace: load the libraries, then build one product image.
    $workerScript = {
        param($ModuleFiles, $ConfigSnapshot, $Batch, $Brands, $Item, $ItemId)
        $ErrorActionPreference = 'Stop'
        foreach ($moduleFile in $ModuleFiles) { . $moduleFile }
        $script:Config = [Management.Automation.PSSerializer]::Deserialize($ConfigSnapshot)
        $script:Batch = $Batch
        Invoke-ProductItem $Item $ItemId $Brands
    }

    # Lock the queue for the whole run. Finished URLs are checkpointed after every item.
    if (-not (Test-Path -LiteralPath $List)) { throw "URL list not found: $List" }
    $queueLock = [IO.File]::Open("$List.lock", [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $pool = $null
    try {
        $queue = Read-UrlQueue $List
        $urls = @($queue.Items)
        if (-not $urls) { Write-Host "No product URLs to process. Add one URL per line to $List"; return }

        $started = Get-Date
        $script:Batch = New-Batch $OutDir
        Write-Lines $script:Batch.InputUrls $queue.Lines
        $completed = New-Object System.Collections.Generic.List[string]
        $results = New-Object System.Collections.Generic.List[object]
        $brands = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
        Save-Csv $results.ToArray() $script:Batch.Csv
        $threads = [Math]::Min($ThrottleLimit, $urls.Count)
        Write-Host "Starting: $($urls.Count) URLs" -ForegroundColor Cyan
        Write-Host "Batch: $($script:Batch.Dir)" -ForegroundColor DarkGray
        Write-Host "Threads: $threads" -ForegroundColor DarkGray

        $pool = [RunspaceFactory]::CreateRunspacePool(1, $threads)
        $pool.Open()
        $jobs = New-Object System.Collections.Generic.List[object]
        $index = 0
        foreach ($item in $urls) {
            $index++
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($workerScript).AddArgument($ModuleFiles).AddArgument($configSnapshot).AddArgument($script:Batch).AddArgument($brands).AddArgument($item).AddArgument(('{0:D3}-{1}' -f $index, $item.Handle))
            $jobs.Add([pscustomobject]@{ Index = $index; Item = $item; PS = $ps; Async = $ps.BeginInvoke(); Seen = 0; Announced = $false; Done = $false })
        }

        # Stream worker output as it arrives; commit each finished item in the main thread.
        # With several threads, every line is tagged (#n) so interleaved lines stay attributable.
        $tag = { param($job) if ($threads -gt 1) { "  (#$($job.Index))" } else { '' } }
        $pending = $jobs.Count
        while ($pending -gt 0) {
            foreach ($job in $jobs) {
                if ($job.Done) { continue }
                $info = $job.PS.Streams.Information
                while ($job.Seen -lt $info.Count) {
                    if (-not $job.Announced) {
                        Write-Host "`n[$($job.Index)/$($urls.Count)] $($job.Item.Handle)" -ForegroundColor Cyan
                        $job.Announced = $true
                    }
                    Write-Host ("$($info[$job.Seen].MessageData)" + (& $tag $job))
                    $job.Seen++
                }
                if (-not $job.Async.IsCompleted) { continue }
                $job.Done = $true; $pending--
                if (-not $job.Announced) { Write-Host "`n[$($job.Index)/$($urls.Count)] $($job.Item.Handle)" -ForegroundColor Cyan }
                try {
                    $result = @($job.PS.EndInvoke($job.Async) | Where-Object { $_ -and $_.PSObject.Properties['photo_path'] })[-1]
                    if (-not $result) { throw 'Worker returned no result.' }
                } catch {
                    $inner = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
                $errorLog = Join-Path $script:Batch.Logs ('{0:D3}-{1}-error.txt' -f $job.Index, $job.Item.Handle)
                @($_ | Out-String; $_.ScriptStackTrace; $job.PS.Streams.Error | Format-List * -Force | Out-String) |
                    Set-Content -LiteralPath $errorLog -Encoding UTF8
                $causeTag = if ($inner -match '\[CAUSE:(AUTH|QUOTA|NETWORK|BUSY|STORE_LOCKED|PRODUCT_TIMEOUT|PRODUCT_NETWORK|PRODUCT_ACCESS|PRODUCT_NOT_FOUND|PRODUCT_DOWNLOAD|MISSING_DATA)\]') { $Matches[0] + ' ' } else { '' }
                Write-Warning "[ITEM $($job.Index)] Failed; ${causeTag}URL and source kept for retry. $inner"
                    continue
                } finally { $job.PS.Dispose() }

                # Commit outside the per-item catch: stop on storage errors to avoid consuming more input.
                Save-ProductCheckpoint $results $result $completed $job.Item $List
                Write-Host "  [OK] [ITEM $($job.Index)] $($result.photo_path -replace '/', '\')$(& $tag $job)" -ForegroundColor Green
            }
            if ($pending -gt 0) { Start-Sleep -Milliseconds 400 }
        }
        Write-MissingDataSummary $script:Batch
        Complete-BatchExport $results (Join-Path $ProjectRoot 'data/names.txt')
        Write-Host "`nDone: $($results.Count)/$($urls.Count) exported in $([int]((Get-Date) - $started).TotalSeconds)s" -ForegroundColor Green
        Write-Host "CSV: $($script:Batch.Csv)"
        Write-Host "Pending: $List" -ForegroundColor DarkGray
        if ($results.Count -lt $urls.Count) {
            throw "Batch incomplete: $($urls.Count - $results.Count) URL(s) failed and remain queued. See $($script:Batch.Logs)"
        }
    } finally {
        if ($pool) { $pool.Close(); $pool.Dispose() }
        $queueLock.Dispose()
    }

}
