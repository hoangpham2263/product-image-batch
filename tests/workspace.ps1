. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
. (Join-Path $project 'src/bootstrap.ps1')
. (Join-Path $project 'src/ui/progress.ps1')
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
    # Windows dialogs: a variable read in a function must be set somewhere (in it, as a parameter, or in its file).
    # Catches leftovers like a removed temp file still cleaned up in a finally block, which broke + Drive.
    $automatic = @('_', 'this', 'true', 'false', 'null', 'args', 'PSScriptRoot', 'Matches', 'LASTEXITCODE', 'ErrorActionPreference', 'PSVersionTable', 'IsWindows', 'IsMacOS', 'HOME', 'PID', 'sender', 'input', 'PSBoundParameters', 'ExecutionContext', 'Error', 'PSCmdlet', 'host', 'OutputEncoding')
    foreach ($uiFile in Get-ChildItem -LiteralPath (Join-Path $project 'src/ui') -Filter *.ps1) {
        $ast = [Management.Automation.Language.Parser]::ParseFile($uiFile.FullName, [ref]$null, [ref]$null)
        $fileSet = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] }, $false) | ForEach-Object { $_.Left.Extent.Text -replace '^\[[^\]]+\]', '' -replace '^\$', '' -replace '[\.\[].*$', '' })
        foreach ($fn in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            $set = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($p in $fn.FindAll({ param($n) $n -is [Management.Automation.Language.ParameterAst] }, $true)) { [void]$set.Add($p.Name.VariablePath.UserPath) }
            foreach ($a in $fn.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] }, $true)) { foreach ($v in $a.Left.FindAll({ param($n) $n -is [Management.Automation.Language.VariableExpressionAst] }, $true)) { [void]$set.Add($v.VariablePath.UserPath) } }
            foreach ($f in $fn.FindAll({ param($n) $n -is [Management.Automation.Language.ForEachStatementAst] }, $true)) { [void]$set.Add($f.Variable.VariablePath.UserPath) }
            foreach ($v in $fn.FindAll({ param($n) $n -is [Management.Automation.Language.VariableExpressionAst] }, $true)) {
                $name = $v.VariablePath.UserPath
                Assert (-not $v.VariablePath.IsUnqualified -or $set.Contains($name) -or $automatic -contains $name -or $fileSet -contains $name) "$($uiFile.Name):$($v.Extent.StartLineNumber) $($fn.Name) reads `$$name, which is never set."
            }
        }
    }
    # The Windows window loads its own scripts: every application function its dialogs call must be loaded there.
    $src = Join-Path $project 'src'
    $window = Get-Content -LiteralPath (Join-Path $src 'ui/main-window.ps1') -Raw
    $ui = (Get-ChildItem -LiteralPath (Join-Path $src 'ui') -Filter *.ps1 | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $src 'application'), (Join-Path $src 'infrastructure') -Filter *.ps1)) {
        $relative = (Split-Path $file.DirectoryName -Leaf) + '/' + $file.Name
        if ($window -match [regex]::Escape("'$relative'")) { continue }
        foreach ($name in @([regex]::Matches((Get-Content -LiteralPath $file.FullName -Raw), '(?m)^function ([\w-]+)') | ForEach-Object { $_.Groups[1].Value })) {
            Assert ($ui -notmatch "(?<![\w-])$([regex]::Escape($name))(?![\w-])") "The Windows window calls $name but does not load $relative."
        }
    }
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
    Assert ((Get-AiModelSummary $fixture) -eq 'gpt-5.5 · suy nghĩ thấp (chọn trong Kiểm tra cấu hình) · qua 9router') "A run must name the chosen model: $(Get-AiModelSummary $fixture)"
    Set-AiSettings $fixture '' ''
    Assert ((Get-AiModelSummary $fixture) -eq 'gpt-5.6-sol · suy nghĩ cao (mặc định của Codex) · qua 9router') "Without a choice a run must name Codex's own model: $(Get-AiModelSummary $fixture)"
    Assert ((ConvertTo-UiEvent 'Model AI: gpt-5.5 · suy nghĩ thấp').Text -eq 'Model AI: gpt-5.5 · suy nghĩ thấp') 'The model line must show in the app log.'
    # The quota line reaches the window as UTF-8 (a redirected console would break the Vietnamese on Windows).
    $quotaFile = Join-Path $fixture 'quota.txt'
    & (Join-Path $project 'src/quota-status.ps1') -OutFile $quotaFile
    $quotaText = [IO.File]::ReadAllText($quotaFile, [Text.Encoding]::UTF8)
    Assert ($quotaText -match '^Hạn mức: ' -and $quotaText -notmatch '\?|\uFFFD') "The quota line must keep its Vietnamese text: $quotaText"
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
