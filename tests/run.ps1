# All checks run in fresh Windows PowerShell 5.1 processes; no paid AI calls.
param([string[]]$Name = @('workspace', 'gui-launch', 'ui-status', 'inline-ui', 'setup-check', 'quota', 'ai-retry', 'cli-process', 'source-data', 'reference-archive', 'product-input', 'product-context', 'reference-fallback', 'scene-selection', 'image-output', 'image-delivery', 'image-feedback', 'manual-references', 'review-writing', 'review-pipeline', 'browser-backend', 'drive-storage'))
$ErrorActionPreference = 'Stop'
# Prefer the Windows PowerShell modules even when launched from PowerShell 7.
$env:PSModulePath = (Join-Path $PSHOME 'Modules') + [IO.Path]::PathSeparator + $env:PSModulePath
$project = Split-Path $PSScriptRoot -Parent
$failures = New-Object Collections.Generic.List[string]
foreach ($file in @(Get-ChildItem (Join-Path $project 'src'), $PSScriptRoot -Recurse -File -Filter '*.ps1')) {
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) { throw ($parseErrors | Out-String) }
}
foreach ($testName in $Name) {
    if ($testName -notmatch '^[a-z][a-z0-9-]+$' -or $testName -eq 'run') { throw "Invalid test name: $testName" }
    $path = Join-Path $PSScriptRoot "$testName.ps1"
    if (-not (Test-Path -LiteralPath $path)) { throw "Test not found: $testName" }
    Write-Host "Testing: $testName" -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path
    if ($LASTEXITCODE -ne 0) { $failures.Add($testName) }
}
if ($failures.Count) { throw "Failed checks: $($failures -join ', ')" }
Write-Host "PASS: syntax and $($Name.Count) test suites." -ForegroundColor Green
