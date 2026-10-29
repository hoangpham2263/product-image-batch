# Gửi log: one zip with what is needed to look into a problem (app logs, the last runs' logs and
# results, the configuration check, version and system) and the reviews marked Bỏ not sent yet, as data to
# improve the images; uploaded to the management page. Returns the zip and the samples it carries.
# Never included: drive.json (the app password), other images and the user's product list.
function New-SupportLogBundle([string]$ProjectRoot) {
    $workspace = Join-Path $ProjectRoot 'workspace'
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $system = if (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows) { 'windows' } else { 'mac' }
    $version = try { Get-AppVersion $ProjectRoot } catch { '' }
    $machine = ([Environment]::MachineName -replace '[^\w-]', '')
    $name = (@($stamp, $version, $system, $machine) | Where-Object { $_ }) -join '_'
    $folder = Join-Path ([IO.Path]::GetTempPath()) "prb-log-$([Guid]::NewGuid().ToString('N'))"
    $content = Join-Path $folder $name
    New-Item -ItemType Directory -Force -Path $content | Out-Null
    try {
        $info = [ordered]@{ created_at = (Get-Date).ToString('o'); version = $version; system = $system; machine = $machine
            os = [Environment]::OSVersion.VersionString; powershell = $PSVersionTable.PSVersion.ToString() }
        $info | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $content 'app.json') -Encoding UTF8
        $check = Join-Path $ProjectRoot 'src/setup-check.ps1'
        try { & $check -AsJson 2>&1 | Out-String | Set-Content -LiteralPath (Join-Path $content 'setup-check.json') -Encoding UTF8 } catch { $_ | Out-String | Set-Content -LiteralPath (Join-Path $content 'setup-check.json') -Encoding UTF8 }
        $logs = Join-Path $workspace 'logs'
        if (Test-Path -LiteralPath $logs) {
            New-Item -ItemType Directory -Force -Path (Join-Path $content 'logs') | Out-Null
            Get-ChildItem -LiteralPath $logs -File | Sort-Object LastWriteTime -Descending | Select-Object -First 40 | Copy-Item -Destination (Join-Path $content 'logs')
        }
        $output = Join-Path $workspace 'output'
        if (Test-Path -LiteralPath $output) {
            foreach ($batch in @(Get-ChildItem -LiteralPath $output -Directory | Sort-Object Name -Descending | Select-Object -First 5)) {
                $target = Join-Path $content "runs/$($batch.Name)"
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                foreach ($file in @('results.json', 'review.json', 'missing-data.csv')) {
                    $path = Join-Path $batch.FullName $file
                    if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $target }
                }
                $batchLogs = Join-Path $batch.FullName 'logs'
                if (Test-Path -LiteralPath $batchLogs) { Copy-Item -LiteralPath $batchLogs -Destination (Join-Path $target 'logs') -Recurse }
            }
        }
        # About 40 MB of samples per send (uploads stop at 50 MB); the rest go with the next Gửi log.
        $samples = @(); $budget = 40MB
        foreach ($sample in @(Get-UnsentRejectedSamples $ProjectRoot)) {
            $size = [long](Get-ChildItem -LiteralPath $sample.FullName -File | Measure-Object Length -Sum).Sum
            if ($samples.Count -and $size -gt $budget) { break }
            New-Item -ItemType Directory -Force -Path (Join-Path $content 'rejected') | Out-Null
            Copy-Item -LiteralPath $sample.FullName -Destination (Join-Path $content 'rejected') -Recurse
            $samples += $sample.FullName; $budget -= $size
        }
        $zip = Join-Path $workspace "temp/$name.zip"
        New-Item -ItemType Directory -Force -Path (Split-Path $zip -Parent) | Out-Null
        Compress-Archive -Path $content -DestinationPath $zip -Force
        return [pscustomobject]@{ Path = $zip; Samples = $samples }
    } finally { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

function Send-SupportLog($Drive, [string]$ZipPath) {
    $name = [Uri]::EscapeDataString([IO.Path]::GetFileName($ZipPath))
    Invoke-RestMethod -Uri "$($Drive.ApiUrl)/api/logs?name=$name" -Method Post -ContentType 'application/zip' -Headers @{ 'x-admin-key' = $Drive.AdminKey } -InFile $ZipPath -TimeoutSec 300 | Out-Null
    return [IO.Path]::GetFileName($ZipPath)
}
