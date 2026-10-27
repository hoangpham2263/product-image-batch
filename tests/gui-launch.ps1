. (Join-Path $PSScriptRoot 'helpers.ps1')
# Exercise the GUI argument builder against real WinForms values and a child PS process.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/ui/main-window.ps1'), [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors | Out-String) }
$builder = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-RunArguments' }, $true)
if (-not $builder) { throw 'GUI argument builder not found.' }
. ([scriptblock]::Create($builder.Extent.Text))
$launcher = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Start-RunProcess' }, $true)
if (-not $launcher) { throw 'GUI asynchronous launcher not found.' }
. ([scriptblock]::Create($launcher.Extent.Text))
Add-Type -AssemblyName System.Windows.Forms
$numPer = New-Object Windows.Forms.NumericUpDown -Property @{ Minimum = 1; Maximum = 6; Value = 6 }
$numThr = New-Object Windows.Forms.NumericUpDown -Property @{ Minimum = 1; Maximum = 4; Value = 3 }
$testDir = Join-Path $TestWorkspaceRoot ('gui launch test ' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
try {
    $entry = Join-Path $testDir 'run-images.ps1'
    @'
param([int]$PhotosPerImage, [int]$ThrottleLimit, [string]$FeedbackFile='', [string]$ApprovedImage='', [string]$ReferenceMapFile='')
[pscustomobject]@{ PhotosPerImage = $PhotosPerImage; ThrottleLimit = $ThrottleLimit; FeedbackFile=$FeedbackFile; ApprovedImage=$ApprovedImage;ReferenceMapFile=$ReferenceMapFile } | ConvertTo-Json -Compress
'@ | Set-Content -LiteralPath $entry -Encoding UTF8
    $runArgs = @(New-RunArguments -ScriptPath $entry -PhotosPerImage ([int]$numPer.Value) -ThrottleLimit ([int]$numThr.Value))
    $out = Join-Path $testDir 'out.log'; $err = Join-Path $testDir 'err.log'
    $child = Start-RunProcess -ArgumentList $runArgs -OutputLog $out -ErrorLog $err
    $child.WaitForExit(); $child.Refresh()
    if ($child.ExitCode -ne 0) { throw (Get-Content -LiteralPath $err -Raw) }
    $values = Get-Content -LiteralPath $out -Raw | ConvertFrom-Json
    if ($values.PhotosPerImage -ne 6 -or $values.ThrottleLimit -ne 3) { throw 'GUI numeric parameters were not received correctly.' }
    if ($null -eq $child.ExitCode -or $child.ExitCode -ne 0) { throw 'Success exit code was lost after asynchronous launch.' }
    $child.Dispose()
    $feedbackPath=Join-Path $testDir "feedback user's correction.json"
    $feedbackArgs=@(New-RunArguments $entry 1 1 $feedbackPath)
    $feedbackChild=Start-RunProcess $feedbackArgs (Join-Path $testDir 'feedback-out.log') (Join-Path $testDir 'feedback-err.log')
    $feedbackChild.WaitForExit();$feedbackChild.Refresh()
    $feedbackValue=Get-Content -LiteralPath (Join-Path $testDir 'feedback-out.log') -Raw|ConvertFrom-Json
    if($feedbackChild.ExitCode -ne 0 -or $feedbackValue.FeedbackFile -ne $feedbackPath){throw 'GUI lost feedback file path containing spaces/apostrophes.'}
    $feedbackChild.Dispose()
    $approvedPath=Join-Path $testDir "user's accepted image.png"
    $approvedArgs=@(New-RunArguments -ScriptPath $entry -PhotosPerImage 1 -ThrottleLimit 1 -ApprovedImage $approvedPath)
    $approvedChild=Start-RunProcess $approvedArgs (Join-Path $testDir 'approved-out.log') (Join-Path $testDir 'approved-err.log')
    $approvedChild.WaitForExit();$approvedChild.Refresh()
    $approvedValue=Get-Content -LiteralPath (Join-Path $testDir 'approved-out.log') -Raw|ConvertFrom-Json
    if($approvedChild.ExitCode -ne 0 -or $approvedValue.ApprovedImage -ne $approvedPath){throw 'GUI approved-image argument was lost.'}
    $approvedChild.Dispose()
    $mapFile=Join-Path $testDir 'reference inputs.json'
    $mapArgs=@(New-RunArguments -ScriptPath $entry -PhotosPerImage 1 -ThrottleLimit 1 -ReferenceMapFile $mapFile)
    $mapChild=Start-RunProcess $mapArgs (Join-Path $testDir 'map-out.log') (Join-Path $testDir 'map-err.log')
    $mapChild.WaitForExit();$mapChild.Refresh()
    $mapValue=Get-Content -LiteralPath (Join-Path $testDir 'map-out.log') -Raw|ConvertFrom-Json
    if($mapChild.ExitCode -ne 0 -or $mapValue.ReferenceMapFile -ne $mapFile){throw 'GUI lost the per-product reference map argument.'}
    $mapChild.Dispose()
    'exit 7' | Set-Content -LiteralPath $entry -Encoding UTF8
    $failed = Start-RunProcess -ArgumentList $runArgs -OutputLog (Join-Path $testDir 'failed-out.log') -ErrorLog (Join-Path $testDir 'failed-err.log')
    $failed.WaitForExit(); $failed.Refresh()
    if ($null -eq $failed.ExitCode -or $failed.ExitCode -ne 7) { throw 'Failure exit code was lost after asynchronous launch.' }
    $failed.Dispose()
    foreach ($invalidThreads in @(0, 5)) {
        $rejected = $false
        try { & (Join-Path $root 'src/run-images.ps1') -ThrottleLimit $invalidThreads | Out-Null }
        catch { $rejected = $_.FullyQualifiedErrorId -like 'ParameterArgumentValidationError*' }
        if (-not $rejected) { throw 'Unsafe thread count was not rejected before starting work.' }
    }
    Write-Host 'PASS: real NumericUpDown values reach PowerShell as integers; script path supports spaces.' -ForegroundColor Green
} finally {
    $numPer.Dispose(); $numThr.Dispose()
    $resolved = [IO.Path]::GetFullPath($testDir)
    $allowed = [IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\') + '\'
    if ($resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'gui launch test *') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
