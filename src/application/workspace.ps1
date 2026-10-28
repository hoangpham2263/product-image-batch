# All project runtime state belongs to this ignored directory.
function Initialize-ProjectWorkspace([string]$ProjectRoot) {
    $root = Join-Path ([IO.Path]::GetFullPath($ProjectRoot)) 'workspace'
    $paths = @{
        Root = $root
        Output = Join-Path $root 'output'
        Logs = Join-Path $root 'logs'
        Temp = Join-Path $root 'temp'
        Tests = Join-Path $root 'tests'
        Queue = Join-Path $root 'urls.txt'
    }
    New-Item -ItemType Directory -Force $paths.Root, $paths.Logs, $paths.Temp, $paths.Tests | Out-Null
    if (-not (Test-Path -LiteralPath $paths.Queue)) { [IO.File]::WriteAllText($paths.Queue, "", [Text.UTF8Encoding]::new($true)) }
    $env:TEMP = $paths.Temp
    $env:TMP = $paths.Temp
    return $paths
}

# Installed release (workspace/version.txt, written by the updater); a git checkout shows its latest tag.
function Get-AppVersion([string]$ProjectRoot) {
    $file = Join-Path $ProjectRoot 'workspace/version.txt'
    if (Test-Path -LiteralPath $file) { return (Get-Content -LiteralPath $file -Raw).Trim() }
    if ((Test-Path -LiteralPath (Join-Path $ProjectRoot '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $tag = git -C $ProjectRoot describe --tags --abbrev=0 2>$null
        if ($tag) { return [string]$tag }
    }
    return ''
}
