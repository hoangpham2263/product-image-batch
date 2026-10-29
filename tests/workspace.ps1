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
    # Model AI: empty keeps Codex's default; a chosen model and level are kept; bad values are refused.
    $ai = Get-AiSettings $fixture
    Assert (-not $ai.model -and -not $ai.effort) 'Without a choice the Codex default must be kept.'
    Set-AiSettings $fixture 'gpt-5.5' 'low'
    $ai = Get-AiSettings $fixture
    Assert ($ai.model -eq 'gpt-5.5' -and $ai.effort -eq 'low') 'The chosen model and reasoning level must be kept.'
    $refused = $false; try { Set-AiSettings $fixture 'gpt 5; rm' 'low' } catch { $refused = $true }
    Assert $refused 'An invalid model name must be refused.'
    Set-AiSettings $fixture '' ''
    Assert (-not (Get-AiSettings $fixture).model) 'Choosing the default again must clear the model.'
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
