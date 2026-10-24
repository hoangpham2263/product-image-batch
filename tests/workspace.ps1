. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
. (Join-Path $project 'src/bootstrap.ps1')
$fixture = Join-Path $TestWorkspaceRoot ('workspace-test-' + [Guid]::NewGuid().ToString('N'))
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
try {
    $base = Join-Path $fixture 'data/source-photos'
    New-Item -ItemType Directory -Force $base | Out-Null
    @{ schema_version = 1; photos = @() } | ConvertTo-Json | Set-Content (Join-Path $base 'catalog.json') -Encoding UTF8
    $paths = Initialize-ProjectWorkspace $fixture
    foreach ($key in @('Output', 'Logs', 'Temp')) {
        Assert ($paths[$key].StartsWith($paths.Root)) "Runtime path outside workspace: $key"
    }
    Assert ((Test-Path -LiteralPath $paths.Queue) -and (Test-Path -LiteralPath $paths.Output -IsValid)) 'Workspace was not initialized.'
    Assert ((Get-SourceCatalog $base).Count -eq 0) 'Empty library must load.'
    Write-Host 'PASS: workspace initialization and runtime paths.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $allowed = [IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('') + ''
    if ($resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'workspace-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
