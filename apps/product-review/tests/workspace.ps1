. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
. (Join-Path $project 'src/bootstrap.ps1')
. (Join-Path $project 'src/application/progress.ps1')
$fixture = Join-Path $TestWorkspaceRoot ('workspace-test-' + [Guid]::NewGuid().ToString('N'))
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
try {
    $base = Join-Path $fixture 'data/source-photos'
    New-Item -ItemType Directory -Force $base | Out-Null
    @{ schema_version = 1; photos = @() } | ConvertTo-Json | Set-Content (Join-Path $base 'catalog.json') -Encoding UTF8
    $paths = Initialize-ProjectWorkspace $fixture
    # The product list shows links short, the full one on hover.
    Assert ((Format-ShortProductUrl 'https://www.bangometay.com/p/ban-go-tu-nhien-chan-tang/') -eq 'bangometay.com › ban-go-tu-nhien-chan-tang') 'The list must show a short link.'
    Assert ((Format-ShortProductUrl 'https://shop.test/products/%C3%A1o-polo.html?v=1') -eq 'shop.test › áo-polo') 'Short links drop the query and decode the name.'
    Assert ((Format-ShortProductUrl 'https://local.invalid/products/manual-1') -like 'Sản phẩm tự thêm*') 'A product added without a link says so.'
    # Model AI: empty keeps Codex's default; a chosen model and level are kept; bad values are refused.
    $ai = Get-AiSettings $fixture
    Assert (-not $ai.model -and -not $ai.effort) 'Without a choice the Codex default must be kept.'
    Set-AiSettings $fixture 'gpt-5.5' 'low'
    $ai = Get-AiSettings $fixture
    Assert ($ai.model -eq 'gpt-5.5' -and $ai.effort -eq 'low') 'The chosen model and reasoning level must be kept.'
    $refused = $false; try { Set-AiSettings $fixture 'gpt 5; rm' 'low' } catch { $refused = $true }
    Assert $refused 'An invalid model name must be refused.'
    $env:CODEX_HOME = Join-Path $fixture 'codex'; New-Item -ItemType Directory -Force $env:CODEX_HOME | Out-Null
    "model = `"gpt-5.6-sol`"`nmodel_reasoning_effort = `"high`"`nmodel_provider = `"9router`"`n[profiles.x]`nmodel = `"other`"" | Set-Content (Join-Path $env:CODEX_HOME 'config.toml')
    Assert ((Get-AiModelSummary $fixture) -eq 'gpt-5.5 · suy nghĩ thấp (chọn trong Cấu hình) · qua 9router') "A run must name the chosen model: $(Get-AiModelSummary $fixture)"
    Set-AiSettings $fixture '' ''
    Assert ((Get-AiModelSummary $fixture) -eq 'gpt-5.6-sol · suy nghĩ cao (mặc định của Codex) · qua 9router') "Without a choice a run must name Codex's own model: $(Get-AiModelSummary $fixture)"
    Assert ((ConvertTo-UiEvent 'Model AI: gpt-5.5 · suy nghĩ thấp').Text -eq 'Model AI: gpt-5.5 · suy nghĩ thấp') 'The model line must show in the app log.'
    $call = ConvertTo-UiEvent '  [AI-CALL] gemini'
    Assert ($call.Kind -eq 'Call' -and $call.Backend -eq 'gemini' -and -not $call.Text) 'Each web AI call must be counted, not logged.'
    $tokens = ConvertTo-UiEvent '  [TOKENS] in=1500 cached=800 out=100 (#2)'
    Assert ($tokens.Kind -eq 'Tokens' -and $tokens.TokensIn -eq 1500 -and $tokens.TokensCached -eq 800 -and $tokens.TokensOut -eq 100 -and -not $tokens.Text) 'Token lines must reach the app as counts, not as log text.'
    Remove-Item Env:\CODEX_HOME
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
