# Tools Hub layout: hub/ is shared, each tool is apps/<id>/ with its tool.json, src/, data/, AGENTS.md and workspace/.
# The hub's own state (installed version, update backups) is in workspace/ at the root.

function Get-HubTools([string]$Root) {
    $apps = Join-Path $Root 'apps'
    if (-not (Test-Path -LiteralPath $apps)) { return @() }
    $tools = @(foreach ($file in @(Get-ChildItem -LiteralPath $apps -Filter tool.json -Recurse -Depth 1 -File | Sort-Object FullName)) {
        $tool = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $tool | Add-Member -NotePropertyName Root -NotePropertyValue $file.DirectoryName -Force
        $tool
    })
    # "order" in tool.json sets the picker's order; tools without it follow, by folder name.
    return @($tools | Sort-Object { if ($null -ne $_.order) { [int]$_.order } else { 99 } }, Root)
}

# The menu's local address for this install, the same as hub/picker.mjs picks on macOS: 46000 + part of the folder's
# SHA-1, so two installs never share it.
function Get-HubWebPort([string]$Root) {
    $sha = [Security.Cryptography.SHA1]::Create()
    try { $hex = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Root)) | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
    return 46000 + ([Convert]::ToInt32($hex.Substring(0, 6), 16) % 1000)
}

# Before Tools Hub the app lived at the root (src/, data/, AGENTS.md, workspace/). An install updated from such a
# version gets the new files beside the old ones; this moves its data into apps/product-review/ and removes the old
# files. Kept at the root: src/gui.ps1 and src/mac/server.mjs, which old shortcuts and the old updater still open.
# A git checkout is never touched.
function Move-LegacyLayout([string]$Root) {
    $app = Join-Path $Root 'apps/product-review'
    if ((Test-Path -LiteralPath (Join-Path $Root '.git')) -or -not (Test-Path -LiteralPath (Join-Path $app 'tool.json'))) { return }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'src/ui/main-window.ps1')) -and -not (Test-Path -LiteralPath (Join-Path $Root 'data'))) { return }
    $move = {
        param($From, $To)
        if (-not (Test-Path -LiteralPath $From)) { return }
        if (-not (Test-Path -LiteralPath $To)) { New-Item -ItemType Directory -Force -Path (Split-Path $To -Parent) | Out-Null; Move-Item -LiteralPath $From -Destination $To; return }
        if ((Test-Path -LiteralPath $From -PathType Container) -and (Test-Path -LiteralPath $To -PathType Container)) {
            foreach ($child in @(Get-ChildItem -LiteralPath $From -Force)) { & $move $child.FullName (Join-Path $To $child.Name) }
            if (-not @(Get-ChildItem -LiteralPath $From -Force).Count) { Remove-Item -LiteralPath $From -Force }
        }
    }
    # The tool's data, login and logs; the version stays with the hub.
    $workspace = Join-Path $Root 'workspace'
    if (Test-Path -LiteralPath $workspace) {
        foreach ($child in @(Get-ChildItem -LiteralPath $workspace -Force | Where-Object Name -notin @('version.txt', 'backups'))) { & $move $child.FullName (Join-Path $app "workspace/$($child.Name)") }
    }
    # This machine's lessons: the old root AGENTS.md is merged into the tool's, as an update would.
    $oldAgents = Join-Path $Root 'AGENTS.md'
    if ((Test-Path -LiteralPath $oldAgents) -and ([IO.File]::ReadAllText($oldAgents)).Contains('<!-- app-lessons:start -->')) {
        $temp = Join-Path ([IO.Path]::GetTempPath()) ('tools-hub-lessons-' + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Force -Path $temp | Out-Null
            Copy-Item -LiteralPath (Join-Path $app 'AGENTS.md') -Destination (Join-Path $temp 'AGENTS.md')
            Copy-Item -LiteralPath $oldAgents -Destination (Join-Path $app 'AGENTS.md') -Force
            Merge-AgentInstructions $temp $app
            Remove-Item -LiteralPath $oldAgents -Force
        } finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # Downloaded sample photos and the installed bridge, so neither has to be fetched again.
    $photos = Join-Path $Root 'data/source-photos'
    if (Test-Path -LiteralPath $photos) {
        foreach ($group in @(Get-ChildItem -LiteralPath $photos -Directory -Force)) { & $move $group.FullName (Join-Path $app "data/source-photos/$($group.Name)") }
    }
    & $move (Join-Path $Root 'bridge/node_modules') (Join-Path $app 'bridge/node_modules')
    foreach ($old in @('data', 'tests', 'tools', 'bridge', 'extension', 'test.cmd', 'test.sh', 'setup.cmd', 'setup.command')) {
        Remove-Item -LiteralPath (Join-Path $Root $old) -Recurse -Force -ErrorAction SilentlyContinue
    }
    $keep = @('gui.ps1', 'mac/server.mjs')
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $Root 'src') -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $relative = $file.FullName.Substring((Join-Path $Root 'src').Length + 1) -replace '\\', '/'
        if ($relative -notin $keep) { Remove-Item -LiteralPath $file.FullName -Force }
    }
    foreach ($dir in @(Get-ChildItem -LiteralPath (Join-Path $Root 'src') -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not @(Get-ChildItem -LiteralPath $dir.FullName -Force).Count) { Remove-Item -LiteralPath $dir.FullName -Force }
    }
}
