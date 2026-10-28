# macOS app backend: the local web UI (src/mac/server.mjs) calls the same application functions the
# Windows window uses. One JSON request per stdin line; each answer is one stdout line prefixed '@@RPC '.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$srcDir = Split-Path $PSScriptRoot -Parent
$root = Split-Path $srcDir -Parent
. (Join-Path $srcDir 'application/workspace.ps1')
. (Join-Path $srcDir 'infrastructure/platform.ps1')
. (Join-Path $srcDir 'infrastructure/drive-storage.ps1')
$workspace = Initialize-ProjectWorkspace $root
. (Join-Path $srcDir 'infrastructure/source-catalog.ps1')
. (Join-Path $srcDir 'infrastructure/source-sync.ps1')
. (Join-Path $srcDir 'application/agent-lessons.ps1')
. (Join-Path $srcDir 'application/image-feedback.ps1')
. (Join-Path $srcDir 'application/manual-references.ps1')
. (Join-Path $srcDir 'infrastructure/csv.ps1')
. (Join-Path $srcDir 'application/batch-review.ps1')
. (Join-Path $srcDir 'ui/progress.ps1')
$mapPath = Join-Path $workspace.Root 'reference-inputs/references.json'
$libraryRoot = Join-Path $root 'data/source-photos'

function Test-HttpUrl([string]$Url) { $uri = $null; [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @('http', 'https') }
function Get-EntryInfo([string]$MapFile, [string]$Url) {
    $entry = @((Read-ManualReferenceMap $MapFile).entries | Where-Object product_url -eq $Url)
    $scenes = @(if ($entry.Count) { Get-ManualScenes $entry[0] | ForEach-Object { [pscustomobject]@{ file = $_.file; ok = (Test-Path -LiteralPath $_.file) } } })
    [pscustomobject]@{ url = $Url; scenes = $scenes; product = $(if ($entry.Count -and $entry[0].product_file) { [string]$entry[0].product_file } else { '' }) }
}
function Assert-DraftRoot([string]$Path) {
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $Path -or -not [IO.Path]::GetFullPath($Path).StartsWith($temp) -or (Split-Path $Path -Leaf) -notmatch '^product-reference-[0-9a-f]{32}$') { throw 'Invalid draft.' }
}
$statusNames = @{ saved = 'Đã lưu, chưa chạy'; running = 'Đang làm lại'; awaiting_review = 'Có ảnh mới, chờ bạn kiểm tra'; accepted = 'Bạn đã xác nhận đúng'; failed = 'Làm lại bị lỗi'; stopped = 'Đã dừng' }

function Invoke-Rpc([string]$Cmd, $A) {
    switch ($Cmd) {
        'state' {
            $map = Read-ManualReferenceMap $mapPath
            $urls = @(if (Test-Path $workspace.Queue) { Get-Content $workspace.Queue -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -Unique })
            $version = try { (Get-Content -LiteralPath (Join-Path $workspace.Root 'version.txt') -Raw -ErrorAction Stop).Trim() } catch { '' }
            return [pscustomobject]@{
                rows = @($urls | ForEach-Object { Get-EntryInfo $mapPath $_ }); fallback = [bool]$map.allow_library_fallback
                library = $map.source_library; group = $map.preferred_source_group; drive = [bool](Test-Path -LiteralPath (Join-Path $workspace.Root 'drive.json'))
                version = $version; output = $workspace.Output; codex = [bool](Get-Command codex -ErrorAction SilentlyContinue)
            }
        }
        'rows' { return @(@($A.urls) | ForEach-Object { Get-EntryInfo $mapPath ([string]$_) }) }
        'groups' { return @(if ($A.local) { Get-SourcePhotoGroups $libraryRoot } else { Get-SourceGroupChoices $root $libraryRoot }) }
        'sourceDir' { return (Get-SourcePhotoDirectory $libraryRoot ([string]$A.group)) }
        'draftOpen' {
            $temp = Join-Path ([IO.Path]::GetTempPath()) ('product-reference-' + [Guid]::NewGuid().ToString('N'))
            $draftMap = Join-Path $temp 'workspace/reference-inputs/references.json'
            New-Item -ItemType Directory -Path (Split-Path $draftMap -Parent) -Force | Out-Null
            Write-FeedbackJson $draftMap (Read-ManualReferenceMap $mapPath)
            return $temp
        }
        'draftInfo' { Assert-DraftRoot $A.root; return (Get-EntryInfo (Join-Path $A.root 'workspace/reference-inputs/references.json') ([string]$A.url)) }
        'draftAttach' {
            Assert-DraftRoot $A.root
            $url = [string]$A.url
            if ($A.role -eq 'Product' -and -not $url) { $url = 'https://local.invalid/products/manual-' + [Guid]::NewGuid().ToString('N') }
            if (-not (Test-HttpUrl $url)) { throw 'Dán link hợp lệ vào dòng này trước khi dán ảnh.' }
            foreach ($path in @($A.paths)) { [void](Save-ManualReference $A.root $url ([string]$path) $(if ($A.role -eq 'Product') { 'Product' } else { 'Scene' })) }
            return $url
        }
        'draftRemoveScene' { Assert-DraftRoot $A.root; Remove-ManualScene (Join-Path $A.root 'workspace/reference-inputs/references.json') ([string]$A.url) ([int]$A.index); return $true }
        'draftRemoveProduct' {
            Assert-DraftRoot $A.root
            $draftMap = Join-Path $A.root 'workspace/reference-inputs/references.json'
            $map = Read-ManualReferenceMap $draftMap
            foreach ($entry in @($map.entries | Where-Object product_url -eq ([string]$A.url))) { $entry.PSObject.Properties.Remove('product_file'); $entry.PSObject.Properties.Remove('product_sha256') }
            $map.entries = @($map.entries | Where-Object { @(Get-ManualScenes $_).Count -or $_.product_file })
            Write-FeedbackJson $draftMap $map
            return $true
        }
        'draftSave' {
            # Same rules as Save-ProductQueueDraft in the Windows window.
            Assert-DraftRoot $A.root
            $url = ([string]$A.url).Trim()
            if (-not (Test-HttpUrl $url)) { throw 'Link sản phẩm không hợp lệ.' }
            if ($url -in @($A.others)) { throw 'Link này đã có trong danh sách.' }
            $entry = @((Read-ManualReferenceMap (Join-Path $A.root 'workspace/reference-inputs/references.json')).entries | Where-Object product_url -eq $url)
            $map = Read-ManualReferenceMap $mapPath; $map.entries = @($map.entries | Where-Object product_url -ne $url)
            New-Item -ItemType Directory -Path (Split-Path $mapPath -Parent) -Force | Out-Null
            Write-FeedbackJson $mapPath $map
            if ($entry.Count) {
                foreach ($scene in @(Get-ManualScenes $entry[0])) { [void](Save-ManualReference $root $url $scene.file) }
                if ($entry[0].product_file) { [void](Save-ManualReference $root $url $entry[0].product_file Product) }
            }
            $map = Read-ManualReferenceMap $mapPath; $map.preferred_source_group = [string]$A.group; Write-FeedbackJson $mapPath $map
            Remove-Item -LiteralPath $A.root -Recurse -Force -ErrorAction SilentlyContinue
            return (Get-EntryInfo $mapPath $url)
        }
        'draftDiscard' { Assert-DraftRoot $A.root; Remove-Item -LiteralPath $A.root -Recurse -Force -ErrorAction SilentlyContinue; return $true }
        'queueSave' {
            # Same rules as Save-ProductQueueEditor in the Windows window.
            $all = @(@($A.urls) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            $duplicates = @($all | Group-Object | Where-Object Count -gt 1)
            if ($duplicates.Count) { throw "Link bị trùng ở nhiều dòng: $($duplicates[0].Name). Mỗi link chỉ nên có một dòng." }
            $urls = @($all | Select-Object -Unique)
            foreach ($url in $urls) { if (-not (Test-HttpUrl $url)) { throw "Link không hợp lệ: $url" } }
            $map = Read-ManualReferenceMap $mapPath; $map.allow_library_fallback = [bool]$A.fallback
            $map.preferred_source_group = [string]$A.group
            $map.source_library = if ($A.library -eq 'local') { 'local' } else { 'drive' }
            if ($A.requireReady -and -not $map.allow_library_fallback) {
                foreach ($url in $urls) {
                    $entry = @($map.entries | Where-Object product_url -eq $url)
                    $scenes = @(if ($entry.Count) { Get-ManualScenes $entry[0] })
                    if (-not $scenes.Count) { throw "Chưa có ảnh bối cảnh: $url" }
                    foreach ($scene in $scenes) {
                        if (-not (Test-Path -LiteralPath $scene.file)) { throw "Chưa có ảnh bối cảnh: $url" }
                        if ((Get-BytesHash ([IO.File]::ReadAllBytes($scene.file))) -ine $scene.sha256) { throw "Ảnh đã thay đổi; hãy gắn lại cho link: $url" }
                    }
                }
            }
            New-Item -ItemType Directory -Path (Split-Path $mapPath -Parent) -Force | Out-Null
            Write-FeedbackJson $mapPath $map
            [IO.File]::WriteAllLines($workspace.Queue, [string[]]$urls, [Text.UTF8Encoding]::new($true))
            return $urls.Count
        }
        'parseLinks' {
            $urls = @(([string]$A.text) -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -Unique)
            foreach ($url in $urls) { if (-not (Test-HttpUrl $url)) { throw "Link không hợp lệ: $url" } }
            return $urls
        }
        'pending' { return (Get-PendingReviewCount ([string]$A.batch)) }
        'reviewBatches' {
            if (-not (Test-Path -LiteralPath $workspace.Output)) { return @() }
            return @(Get-ChildItem -LiteralPath $workspace.Output -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'results.json') } | Sort-Object Name -Descending | Select-Object -First 30 | ForEach-Object {
                    [pscustomobject]@{ label = $_.Name + $(if (Test-Path -LiteralPath (Join-Path $_.FullName 'loox_import.csv')) { '  • đã xuất' } else { '' }); path = $_.FullName }
                })
        }
        'reviewItems' {
            return @(Get-BatchReview ([string]$A.batch) | ForEach-Object {
                    [pscustomobject]@{ id = $_.Id; handle = [string]$_.Row.product_handle; body = [string]$_.Row.body; image = $_.ImagePath; product = $_.ProductPath; decision = $_.Decision }
                })
        }
        'reviewDecide' { Set-BatchReviewDecision ([string]$A.batch) ([string]$A.id) ([string]$A.decision); return $true }
        'reviewExport' { return (Export-ReviewedCsv ([string]$A.batch)) }
        'feedbackChoices' {
            if (-not (Test-Path -LiteralPath $workspace.Output)) { return @() }
            return @(Get-ChildItem -LiteralPath $workspace.Output -Directory | Sort-Object Name -Descending | Select-Object -First 30 | ForEach-Object {
                    $images = Join-Path $_.FullName 'images'; if (Test-Path -LiteralPath $images) { Get-ChildItem -LiteralPath $images -File -Filter '*.png' }
                } | Select-Object -First 200 | ForEach-Object { [pscustomobject]@{ label = "$($_.Directory.Parent.Name) / $($_.Name)"; image = $_.FullName } })
        }
        'feedbackTarget' { $t = Get-FeedbackTarget ([string]$A.image); return [pscustomobject]@{ product = $t.ProductPath; image = $t.ImagePath; title = [string]$t.Manifest.product } }
        'feedbackSave' { return (Save-ImageFeedback $root ([string]$A.image) ([string]$A.text) $(if ($A.scope -eq 'category') { 'category' } else { 'product' }) ([bool]$A.remember)) }
        'feedbackHistory' {
            $feedbackRoot = Join-Path $root 'workspace/feedback'
            if (-not (Test-Path -LiteralPath $feedbackRoot)) { return @() }
            return @(Get-ChildItem -LiteralPath $feedbackRoot -Directory | Sort-Object LastWriteTimeUtc -Descending | ForEach-Object {
                    $path = Join-Path $_.FullName 'feedback.json'
                    if (Test-Path -LiteralPath $path) { try { $r = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json; [pscustomobject]@{ label = "$($r.created_at) • $($statusNames[$r.status]) • $($r.product)"; path = $path } } catch { Write-Verbose $_ } }
                })
        }
        'feedbackDetails' {
            $r = Get-Content -LiteralPath ([string]$A.path) -Raw -Encoding UTF8 | ConvertFrom-Json
            $r.remember = [bool]@(Read-AgentLessons (Join-Path $root 'AGENTS.md') | Where-Object id -eq $r.id).Count
            return "Sản phẩm: $($r.product_url)`r`nTrạng thái: $($statusNames[$r.status])`r`nPhạm vi: $($r.scope) • Dùng làm bài học: $($r.remember)`r`n`r`nYêu cầu sửa:`r`n$($r.requested_change)`r`n`r`nKết quả mới: $($r.result_folder)`r`nLỗi: $($r.error)`r`nPhản hồi trước: $($r.parent_feedback_id)"
        }
        'feedbackAccept' { Set-ImageFeedbackStatus ([string]$A.path) accepted; return $true }
        'feedbackToggle' {
            $r = Get-Content -LiteralPath ([string]$A.path) -Raw -Encoding UTF8 | ConvertFrom-Json
            $enabled = [bool]@(Read-AgentLessons (Join-Path $root 'AGENTS.md') | Where-Object id -eq $r.id).Count
            Set-ImageFeedbackRemember $root ([string]$A.path) (-not $enabled); return $true
        }
        'feedbackRecord' { return (Get-Content -LiteralPath ([string]$A.path) -Raw -Encoding UTF8 | ConvertFrom-Json) }
        'feedbackStatus' { Set-ImageFeedbackStatus ([string]$A.path) ([string]$A.status) ([string]$A.folder) ([string]$A.error); return $true }
        'driveLogin' { Connect-DriveAccount $workspace.Root ([string]$A.password); return $true }
        'driveLogout' { Disconnect-DriveAccount $workspace.Root; return $true }
        'event' { return (ConvertTo-UiEvent ([string]$A.line) ([int]$A.index)) }
        'updateCheck' { return (& (Join-Path $srcDir 'update.ps1') -Root $root -Check) }
        'openPath' { $p = [string]$A.path; New-Item -ItemType Directory -Force $p -ErrorAction SilentlyContinue | Out-Null; Open-SystemPath $p; return $true }
        'revealPath' { & open -R ([string]$A.path); return $true }
        default { throw "Unknown command: $Cmd" }
    }
}

while ($null -ne ($line = [Console]::In.ReadLine())) {
    if (-not $line.Trim()) { continue }
    $request = $line | ConvertFrom-Json
    try { $answer = @{ id = $request.id; ok = $true; result = (Invoke-Rpc $request.cmd $request.args) } }
    catch { $answer = @{ id = $request.id; ok = $false; error = $_.Exception.Message } }
    [Console]::Out.WriteLine('@@RPC ' + ($answer | ConvertTo-Json -Depth 8 -Compress))
    [Console]::Out.Flush()
}
