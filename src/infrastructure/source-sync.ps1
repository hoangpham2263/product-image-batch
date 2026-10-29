# Source library on Google Drive (Worker /api/sources): one Drive folder per group. A run downloads
# only the chosen group into data/source-photos/<group>/ and fetches only new or changed files (md5).
function Get-RemoteSourceGroups($Drive) {
    $result = Invoke-RestMethod -Uri "$($Drive.ApiUrl)/api/sources" -Headers @{ 'x-admin-key' = $Drive.AdminKey } -TimeoutSec 15
    return @($result.groups | ForEach-Object { [string]$_.name })
}

# Groups for the picker: Drive groups (read once per app session) plus folders already on this machine.
function Get-SourceGroupChoices([string]$ProjectRoot, [string]$LibraryRoot) {
    if ($null -eq $script:RemoteSourceGroups) {
        $script:RemoteSourceGroups = @(try {
            $drive = Get-DriveConfig (Join-Path $ProjectRoot 'workspace')
            if ($drive) { Get-RemoteSourceGroups $drive }
        } catch { Write-Verbose $_ })
    }
    $local = @(if (Test-Path -LiteralPath $LibraryRoot) { Get-ChildItem -LiteralPath $LibraryRoot -Directory | ForEach-Object { $_.Name.Normalize([Text.NormalizationForm]::FormC) } })
    if (-not ($script:RemoteSourceGroups + $local).Count) { return @(Get-SourcePhotoGroups $LibraryRoot) }
    return @($script:RemoteSourceGroups + $local | Sort-Object -Unique |
        Sort-Object @{ Expression = { if ($_ -eq 'Áo') { 0 } elseif ($_ -eq 'Nội thất') { 1 } else { 2 } } }, @{ Expression = { $_ } })
}

function Sync-SourceGroup($Drive, [string]$SourceDir, [string]$Group) {
    $Group = $Group.Normalize([Text.NormalizationForm]::FormC)
    $folder = Get-SourcePhotoDirectory $SourceDir $Group
    $listing = Invoke-RestMethod -Uri "$($Drive.ApiUrl)/api/sources/$([Uri]::EscapeDataString($Group))" -Headers @{ 'x-admin-key' = $Drive.AdminKey } -TimeoutSec 60
    # name -> md5 of the files earlier syncs wrote; only these are ever removed again.
    $indexPath = Join-Path $folder '.drive-sync.json'
    $index = @{}
    if (Test-Path -LiteralPath $indexPath) {
        foreach ($p in (Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties) { $index[$p.Name] = [string]$p.Value }
    }
    $remote = @{}
    $missing = New-Object Collections.Generic.List[object]
    foreach ($file in @($listing.files)) {
        $name = [string]$file.name
        if (-not $name -or [IO.Path]::GetFileName($name) -ne $name -or $name.EndsWith('.part')) { continue }
        $remote[$name] = $true
        if ($index[$name] -ne $file.md5 -or -not (Test-Path -LiteralPath (Join-Path $folder $name))) { $missing.Add($file) }
    }
    $removed = 0
    foreach ($name in @($index.Keys)) {
        if ($remote[$name]) { continue }
        Remove-Item -LiteralPath (Join-Path $folder $name) -Force -ErrorAction SilentlyContinue
        $index.Remove($name); $removed++
    }
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromMinutes(2)
    $done = 0
    try {
        # Eight downloads at a time; the index is saved after each batch so a stopped sync resumes.
        for ($at = 0; $at -lt $missing.Count; $at += 8) {
            $batch = @($missing | Select-Object -Skip $at -First 8)
            $tasks = @($batch | ForEach-Object { $client.GetByteArrayAsync([string]$_.url) })
            [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$tasks)
            for ($i = 0; $i -lt $batch.Count; $i++) {
                [IO.File]::WriteAllBytes((Join-Path $folder $batch[$i].name), $tasks[$i].Result)
                $index[[string]$batch[$i].name] = [string]$batch[$i].md5
            }
            $done += $batch.Count
            $index | ConvertTo-Json | Set-Content -LiteralPath $indexPath -Encoding UTF8
            Write-Host "  [SOURCE] $Group`: $done/$($missing.Count)" -ForegroundColor Cyan
        }
    } finally { $client.Dispose() }
    $index | ConvertTo-Json | Set-Content -LiteralPath $indexPath -Encoding UTF8
    # Older installs kept the uncompressed originals under their previous names; drop them so they
    # are not picked as extra uncatalogued photos.
    foreach ($entry in @(Get-SampleCatalogEntries $SourceDir)) {
        foreach ($old in @($entry.previous_files)) {
            if (-not $old -or $old -eq $entry.file -or $old -notmatch '^[^/\\]+/[^/\\]+$') { continue }
            Remove-Item -LiteralPath (Join-Path $SourceDir $old) -Force -ErrorAction SilentlyContinue
        }
    }
    return [pscustomobject]@{ Group = $Group; Total = $remote.Count; Downloaded = $done; Removed = $removed }
}

# Images of one group already on this machine (after Đồng bộ), for the "Từ kho Drive" picker.
function Get-LocalSourceFiles([string]$SourceDir, [string]$Group) {
    $folder = Join-Path $SourceDir $Group.Normalize([Text.NormalizationForm]::FormC)
    if (-not (Test-Path -LiteralPath $folder)) { return @() }
    return @(Get-ChildItem -LiteralPath $folder -File | Where-Object { $_.Extension -match '^\.(png|jpe?g)$' } | Sort-Object Name | ForEach-Object FullName)
}

# A group's images on Drive, each with the local copy when one is already in place (synced or picked).
function Get-SourceGroupFiles($Drive, [string]$SourceDir, [string]$Group) {
    $Group = $Group.Normalize([Text.NormalizationForm]::FormC)
    $folder = Join-Path $SourceDir $Group
    $index = Read-SourceSyncIndex $folder
    $listing = Invoke-RestMethod -Uri "$($Drive.ApiUrl)/api/sources/$([Uri]::EscapeDataString($Group))" -Headers @{ 'x-admin-key' = $Drive.AdminKey } -TimeoutSec 60
    foreach ($file in @($listing.files)) {
        $name = [string]$file.name
        if (-not $name -or [IO.Path]::GetFileName($name) -ne $name) { continue }
        $path = Join-Path $folder $name
        $local = if ($index[$name] -eq $file.md5 -and (Test-Path -LiteralPath $path)) { $path } else { '' }
        [pscustomobject]@{ name = $name; md5 = [string]$file.md5; url = [string]$file.url; local = $local }
    }
}

# Uses picked Drive images directly: downloads only the ones not on this machine yet, into the group
# folder and its sync index, so a later Đồng bộ never downloads them twice. Returns local paths.
function Save-SourceGroupFiles([string]$SourceDir, [string]$Group, [object[]]$Files) {
    $folder = Get-SourcePhotoDirectory $SourceDir $Group.Normalize([Text.NormalizationForm]::FormC)
    $index = Read-SourceSyncIndex $folder
    foreach ($file in @($Files)) {
        $name = [IO.Path]::GetFileName([string]$file.name)
        if (-not $name) { continue }
        $path = Join-Path $folder $name
        if ($index[$name] -ne $file.md5 -or -not (Test-Path -LiteralPath $path)) {
            Invoke-WebRequest -Uri ([string]$file.url) -OutFile $path -UseBasicParsing -TimeoutSec 120
            $index[$name] = [string]$file.md5
            $index | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder '.drive-sync.json') -Encoding UTF8
        }
        $path
    }
}

function Read-SourceSyncIndex([string]$Folder) {
    $index = @{}
    $indexPath = Join-Path $Folder '.drive-sync.json'
    if (Test-Path -LiteralPath $indexPath) {
        foreach ($p in (Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties) { $index[$p.Name] = [string]$p.Value }
    }
    return $index
}
