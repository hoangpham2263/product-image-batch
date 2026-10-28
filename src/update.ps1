# Run from the app's Cập nhật button: bring the app files up to the latest GitHub Release (vX.Y.Z).
# Git checkouts use git pull; ZIP installs download the newest release ZIP. User data is never touched.
# -Check prints the newer version ('' when current); -Apply installs it (the app reopens itself afterwards).
param([string]$Root = (Split-Path $PSScriptRoot -Parent), [switch]$NoRun, [switch]$Check, [switch]$Apply)
$ErrorActionPreference = 'Stop'
$script:Repo = 'hoangpham2263/product-review-batch'
# Local data and lessons the app writes; an update keeps them as they are.
$script:KeepPaths = @('workspace', '.git', 'AGENTS.md', 'bridge/node_modules')

function Copy-AppUpdate([string]$Source, [string]$Target) {
    foreach ($file in @(Get-ChildItem -LiteralPath $Source -Recurse -File -Force)) {
        $relative = $file.FullName.Substring($Source.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        if (@($script:KeepPaths | Where-Object { $relative -eq $_ -or $relative.StartsWith("$_/") }).Count) { continue }
        $destination = Join-Path $Target $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
}

function Get-LatestRelease {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    return Invoke-RestMethod -Uri "https://api.github.com/repos/$script:Repo/releases/latest" -Headers @{ 'User-Agent' = 'product-review-batch' } -TimeoutSec 10
}

function Get-AppUpdate([string]$Root) {
    if (Test-Path -LiteralPath (Join-Path $Root '.git')) {
        git -C $Root fetch --quiet 2>$null | Out-Null
        $behind = git -C $Root rev-list --count 'HEAD..@{u}' 2>$null
        return $(if ([int]$behind -gt 0) { 'git' } else { '' })
    }
    $latest = (Get-LatestRelease).tag_name
    $versionFile = Join-Path $Root 'workspace/version.txt'
    $current = if (Test-Path -LiteralPath $versionFile) { (Get-Content -LiteralPath $versionFile -Raw).Trim() } else { '' }
    return $(if ($latest -match '^v\d+(\.\d+)*$' -and $latest -ne $current) { $latest } else { '' })
}

function Update-App([string]$Root) {
    if (Test-Path -LiteralPath (Join-Path $Root '.git')) {
        if (Get-Command git -ErrorAction SilentlyContinue) { git -C $Root pull --ff-only --quiet 2>$null | Out-Null }
        return
    }
    $headers = @{ 'User-Agent' = 'product-review-batch' }
    $release = Get-LatestRelease
    $latest = $release.tag_name
    $asset = @($release.assets | Where-Object name -eq 'product-review-batch.zip')
    if ($latest -notmatch '^v\d+(\.\d+)*$' -or -not $asset.Count) { return }
    $versionFile = Join-Path $Root 'workspace/version.txt'
    if ((Test-Path -LiteralPath $versionFile) -and (Get-Content -LiteralPath $versionFile -Raw).Trim() -eq $latest) { return }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('pib-update-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        $zip = Join-Path $temp 'app.zip'
        Invoke-WebRequest -Uri $asset[0].browser_download_url -Headers $headers -OutFile $zip -UseBasicParsing -TimeoutSec 120
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $temp 'x') -Force
        $source = @(Get-ChildItem -LiteralPath (Join-Path $temp 'x') -Directory)[0].FullName
        if (-not (Test-Path -LiteralPath (Join-Path $source 'src/gui.ps1'))) { throw 'ZIP không đúng cấu trúc app.' }
        Copy-AppUpdate $source $Root
        New-Item -ItemType Directory -Force -Path (Split-Path $versionFile -Parent) | Out-Null
        Set-Content -LiteralPath $versionFile -Value $latest -Encoding ASCII
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($Check) { return (Get-AppUpdate $Root) }
if ($Apply) { Update-App $Root }
