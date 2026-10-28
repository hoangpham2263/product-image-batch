# Runs before the app opens: bring the app files up to the latest GitHub Release (vX.Y.Z).
# Git checkouts use git pull; ZIP installs download the newest release ZIP. User data is never touched.
param([string]$Root = (Split-Path $PSScriptRoot -Parent), [switch]$NoRun)
$ErrorActionPreference = 'Stop'
$script:Repo = 'hoangpham2263/product-image-batch'
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

function Update-App([string]$Root) {
    if (Test-Path -LiteralPath (Join-Path $Root '.git')) {
        if (Get-Command git -ErrorAction SilentlyContinue) { git -C $Root pull --ff-only --quiet 2>$null | Out-Null }
        return
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'product-image-batch' }
    $latest = (Invoke-RestMethod -Uri "https://api.github.com/repos/$script:Repo/releases/latest" -Headers $headers -TimeoutSec 10).tag_name
    if ($latest -notmatch '^v\d+(\.\d+)*$') { return }
    $versionFile = Join-Path $Root 'workspace/version.txt'
    if ((Test-Path -LiteralPath $versionFile) -and (Get-Content -LiteralPath $versionFile -Raw).Trim() -eq $latest) { return }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('pib-update-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        $zip = Join-Path $temp 'app.zip'
        Invoke-WebRequest -Uri "https://codeload.github.com/$script:Repo/zip/refs/tags/$latest" -Headers $headers -OutFile $zip -UseBasicParsing -TimeoutSec 120
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $temp 'x') -Force
        $source = @(Get-ChildItem -LiteralPath (Join-Path $temp 'x') -Directory)[0].FullName
        if (-not (Test-Path -LiteralPath (Join-Path $source 'src/gui.ps1'))) { throw 'ZIP không đúng cấu trúc app.' }
        Copy-AppUpdate $source $Root
        New-Item -ItemType Directory -Force -Path (Split-Path $versionFile -Parent) | Out-Null
        Set-Content -LiteralPath $versionFile -Value $latest -Encoding ASCII
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

# No network or GitHub down: open the version already on this machine.
if (-not $NoRun) { try { Update-App $Root } catch { Write-Verbose $_ } }
