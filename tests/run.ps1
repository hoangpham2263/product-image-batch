# All checks run in fresh PowerShell processes (Windows PowerShell 5.1 on Windows, pwsh on macOS); no paid AI calls.
param([string[]]$Name = @('csv', 'workspace', 'gui-launch', 'ui-status', 'inline-ui', 'setup-check', 'quota', 'ai-retry', 'cli-process', 'source-data', 'reference-archive', 'product-input', 'manual-product', 'product-context', 'reference-fallback', 'scene-selection', 'image-output', 'image-delivery', 'image-tool-errors', 'manual-references', 'review-writing', 'review-metadata', 'review-pipeline', 'browser-backend', 'drive-storage', 'drive-delivery', 'multi-scene', 'batch-review', 'app-update', 'support-logs', 'batch-import'))
$ErrorActionPreference = 'Stop'
$onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
# WinForms suites test the Windows desktop window and are skipped on macOS.
$windowsOnly = @('gui-launch', 'ui-status', 'inline-ui', 'manual-references')
if ($onWindows) {
    # Prefer the Windows PowerShell modules even when launched from PowerShell 7.
    $env:PSModulePath = (Join-Path $PSHOME 'Modules') + [IO.Path]::PathSeparator + $env:PSModulePath
    $runner = 'powershell.exe'
} else {
    # pwsh installed as a dotnet tool runs inside dotnet, so prefer the pwsh command over the process path.
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    $runner = if ($pwsh) { $pwsh.Source } else { (Get-Process -Id $PID).Path }
    $Name = @($Name | Where-Object { $_ -notin $windowsOnly })
}
$project = Split-Path $PSScriptRoot -Parent
$failures = New-Object Collections.Generic.List[string]
foreach ($file in @(Get-ChildItem (Join-Path $project 'src'), $PSScriptRoot -Recurse -File -Filter '*.ps1')) {
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) { throw ($parseErrors | Out-String) }
    # Windows PowerShell 5.1 reads a file without a BOM as ANSI and garbles Vietnamese text.
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if (-not $hasBom -and @($bytes | Where-Object { $_ -gt 127 }).Count) { throw "Save as UTF-8 with BOM: $($file.FullName)" }
}
foreach ($testName in $Name) {
    if ($testName -notmatch '^[a-z][a-z0-9-]+$' -or $testName -eq 'run') { throw "Invalid test name: $testName" }
    $path = Join-Path $PSScriptRoot "$testName.ps1"
    if (-not (Test-Path -LiteralPath $path)) { throw "Test not found: $testName" }
    Write-Host "Testing: $testName" -ForegroundColor Cyan
    & $runner -NoProfile -ExecutionPolicy Bypass -File $path
    if ($LASTEXITCODE -ne 0) { $failures.Add($testName) }
}
if ($failures.Count) { throw "Failed checks: $($failures -join ', ')" }
Write-Host "PASS: syntax and $($Name.Count) test suites." -ForegroundColor Green
