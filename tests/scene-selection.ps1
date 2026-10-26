. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$temp = Join-Path $TestWorkspaceRoot ('scene-selection-' + [Guid]::NewGuid().ToString('N'))
try {
    $source = Join-Path $temp 'dining-tables'
    New-Item -ItemType Directory -Path $source -Force | Out-Null
    foreach ($n in 1..3) { 'fixture' | Set-Content (Join-Path $source "$n.jpg") }
    $script:Config = @{SourceDir=$temp;MaxTries=3}
    $script:Batch = @{Logs=$temp}
    $context = [pscustomobject]@{product='Dining table with 12 chairs';presentation='placed';setting='spacious dining room';source_categories=@('dining-tables');reject='implausible scale'}
    $script:Checks=0
    function Invoke-AI($PromptText, $Images, $ResultFile) {
        Assert ($PromptText -match 'chair count alone are not rejection reasons' -and $PromptText -match 'adequate visible space') 'Room compatibility must be checked independently of reference furniture design.'
        Assert ($PromptText -match 'NOFIT: followed by one short concrete reason') 'Missing rejection diagnosis.'
        $script:Checks++
        if ($script:Checks -lt 3) { return 'NOFIT: room is too cramped for the complete set' }
        return 'FIT'
    }
    $chosen = Select-Photo 'product.jpg' 'table' '001-table' @() Scene $context
    Assert ($script:Checks -eq 3 -and (Test-Path $chosen)) 'Object scene search stopped after only two candidates.'
    $evidence=Get-Content (Join-Path $temp '001-table-fit-1.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($evidence.photo -like '*.jpg' -and $evidence.verdict -match 'too cramped') 'Rejected photo and reason were not retained.'
    Write-Host 'PASS: object scenes use configured search budget; room capacity, source design and rejection evidence.' -ForegroundColor Green
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    $allowed=[IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\')+'\'
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'scene-selection-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
