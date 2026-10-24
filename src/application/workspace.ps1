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
