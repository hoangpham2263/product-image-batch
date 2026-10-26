. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$tempDir = Join-Path $TestWorkspaceRoot ('review-writing-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    $path = Join-Path $tempDir 'samples.jsonl'
    @(
        '{"category":"coffee-tables","body":"The curved legs stand out against the broad wooden top.","source_url":"https://example.test/table"}'
        '{"category":"coffee-tables","body":"The low shape leaves a clear view across the room."}'
        '{"category":"coffee-tables","body":"Dark edges frame the lighter grain in the middle."}'
        '{"category":"coffee-tables","body":"The rounded corners give the wide top a softer outline."}'
        '{"category":"coffee-tables","body":"The curved legs stand out against the broad wooden top."}'
        '{"category":"tees-hoodies","body":"APPAREL_ONLY The neckline has a contrasting trim."}'
        '{"category":"shop","body":"Generic store feedback should not be selected."}'
        '{"review_id":"legacy-photo","body":"The little front pockets stand out on the dark apron."}'
        '{"source_url":"https://example.test/products/polo-shirt","body":"The collar has a narrow contrasting edge."}'
        'broken json'
    ) | Set-Content $path -Encoding UTF8
    $profiles = @(Get-ProductContexts (Join-Path $root 'data/product-contexts.json'))
    $catalog = @{ photo = [pscustomobject]@{review_id='legacy-photo';category='aprons'} }
    $samples = @(Get-ReviewSamples $path $profiles $catalog)
    Assert ($samples.Count -eq 7) 'Loader failed to deduplicate, filter or infer legacy categories.'
    Assert (@(Get-ReviewSamples (Join-Path $tempDir 'missing.jsonl') $profiles $catalog).Count -eq 0) 'Missing data must allow fallback.'
    $context = [pscustomobject]@{id='coffee-tables';source_categories=@('coffee-tables');presentation='placed';product='wood coffee table';details='rounded top and visible grain'}
    $first = @(Select-ReviewSamples $samples $context 0)
    $second = @(Select-ReviewSamples $samples $context 1)
    Assert ($first.Count -eq 3 -and @($first | Where-Object category -ne coffee-tables).Count -eq 0) 'Unrelated reviews selected.'
    Assert ($first[0].body -ne $second[0].body) 'Reference windows did not rotate.'
    $unknown = [pscustomobject]@{id='unknown';source_categories=@('unknown')}
    Assert (@(Select-ReviewSamples $samples $unknown 0).Count -eq 0) 'Unrelated categories must not be a generic fallback.'
    $dining = [pscustomobject]@{id='dining-tables';source_categories=@('dining-tables')}
    Assert (@(Select-ReviewSamples $samples $dining 0).Count -eq 3) 'Related table fallback is missing.'
    Assert ([bool](Get-ReviewDraftIssue 'I really like the rounded edge.' $first)) 'Formulaic opening passed.'
    Assert ([bool](Get-ReviewDraftIssue 'LOVE the rounded edge.' $first)) 'Fragment opening passed.'
    Assert ([bool](Get-ReviewDraftIssue ($first[0].body) $first)) 'Copied review passed.'
    Assert ([bool](Get-ReviewDraftIssue ('Nice table. '+$first[0].body) $first)) 'Copied phrase passed.'
    Assert (-not (Get-ReviewDraftIssue 'The pale grain is easy to see across the broad top.' $first)) 'Original detail-led draft rejected.'

    $script:Config = @{ ReviewSamples=$samples; ReviewStyles=@(Get-ReviewStyleProfiles (Join-Path $root 'data/review-style.json')); WritingStyle=(Get-WritingStyle (Join-Path $root 'data/writing-style.json')) }
    $script:Batch = @{Logs=$tempDir}
    $script:Calls = 0; $script:Mode = 'opening'
    function Invoke-AI($PromptText, $Images, $ResultFile) {
        $script:Calls++
        Assert ($PromptText -match 'Reference review examples' -and $PromptText -match 'curved legs') 'Actual review samples missing from prompt.'
        Assert ($PromptText -notmatch 'APPAREL_ONLY|specific shirt detail|casual first-person') 'Unrelated clothing or forced first person leaked into table prompt.'
        Assert ($PromptText -match 'untrusted source data' -and $PromptText -match 'Do not copy their wording') 'Reference data constraints missing.'
        if ($script:Mode -eq 'always-bad') { return 'I love the table.' }
        if ($script:Calls -eq 1) {
            if ($script:Mode -eq 'copy') { return $first[0].body }
            return 'I like the wood finish.'
        }
        Assert ($PromptText -match 'Inspection found:') 'Repair must include the concrete failure.'
        return 'The pale grain is easy to see across the broad top.'
    }
    $draft = New-Review 'https://example.test/table' 'table' 'photo.png' '001-table' $context
    Assert ($script:Calls -eq 2 -and $draft -match '^The pale grain') 'Generic opener was not repaired.'
    $evidence = Get-Content (Join-Path $tempDir '001-table-review-sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($evidence.Count -eq 3 -and $evidence[0].source_url -eq 'https://example.test/table') 'Selected evidence was not saved.'
    $script:Calls=0; $script:Mode='copy'
    New-Review 'https://example.test/table' 'table' 'photo.png' '001-table' $context | Out-Null
    Assert ($script:Calls -eq 2) 'Copied review was not repaired.'
    $script:Calls=0; $script:Mode='always-bad'; $failed=$false
    try { New-Review 'https://example.test/table' 'table' 'photo.png' '001-table' $context | Out-Null } catch {
        if ($_.Exception.Message -notlike 'Review quality check failed:*') { throw }; $failed=$true
    }
    Assert ($failed -and $script:Calls -eq 2) 'Repeatedly invalid drafts must stop after one repair.'
    Write-Host 'PASS: categorized source reviews, rotation, prompt evidence, bounded opener/copy repair.' -ForegroundColor Green
} finally {
    $resolved = [IO.Path]::GetFullPath($tempDir)
    $allowed = [IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\') + '\'
    if ($resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'review-writing-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
