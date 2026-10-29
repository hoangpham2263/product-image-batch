. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/update.ps1') -NoRun
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('app-update-'+[Guid]::NewGuid().ToString('N'))
try{
    $new=Join-Path $temp 'new';$app=Join-Path $temp 'app'
    foreach($p in @("$new/src/gui.ps1","$new/AGENTS.md","$new/workspace/drive.json","$app/src/gui.ps1","$app/AGENTS.md","$app/workspace/drive.json")){New-Item -ItemType File -Force -Path $p|Out-Null}
    Set-Content "$new/src/gui.ps1" 'new';Set-Content "$new/src/added.ps1" 'added' -Force
    Set-Content "$new/AGENTS.md" 'upstream';Set-Content "$new/workspace/drive.json" 'upstream'
    Set-Content "$app/AGENTS.md" 'my lessons';Set-Content "$app/workspace/drive.json" 'my login'
    Copy-AppUpdate $new $app
    Assert ((Get-Content "$app/src/gui.ps1") -eq 'new' -and (Test-Path "$app/src/added.ps1")) 'App files must be updated and new files added.'
    Assert ((Get-Content "$app/AGENTS.md") -eq 'my lessons' -and (Get-Content "$app/workspace/drive.json") -eq 'my login') 'Lessons and workspace must be kept.'
    # The check names the new version for ZIP installs and git checkouts alike.
    function Get-LatestRelease { [pscustomobject]@{ tag_name = 'v1.0.15' } }
    Set-Content "$app/workspace/version.txt" 'v1.0.14'
    Assert ((Get-AppUpdate $app) -eq 'v1.0.15') 'A ZIP install must be offered the newer version by name.'
    Set-Content "$app/workspace/version.txt" 'v1.0.15'
    Assert (-not (Get-AppUpdate $app)) 'The newest version must not be offered again.'
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $repo=Join-Path $temp 'checkout';New-Item -ItemType Directory -Force -Path $repo|Out-Null
        git -C $repo init --quiet;git -C $repo -c user.name=t -c user.email=t@t commit --quiet --allow-empty -m init;git -C $repo tag v1.0.14
        Assert ((Get-AppUpdate $repo) -eq 'v1.0.15') 'A git checkout must be offered the newer version by name, not just told there is one.'
    }
    # Opening the app never updates it: only the Cập nhật dialog's button installs (Windows: update-dialog.ps1
    # runs -Apply; macOS: the dialog posts /api/update). Launchers and background checks only run -Check.
    $installers=@(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -File -Include *.ps1,*.mjs,*.js,*.cmd,*.command|Where-Object{$_.Name -ne 'update.ps1' -and (Get-Content -LiteralPath $_.FullName -Raw) -match "Update-App|'-Apply'|/api/update"}|ForEach-Object Name|Sort-Object -Unique)
    foreach($launcher in @('start-app.cmd','start-app.command')){Assert ((Get-Content -LiteralPath (Join-Path $root $launcher) -Raw) -notmatch 'update') "$launcher must not update the app."}
    Assert (($installers -join ',') -eq 'app.js,server.mjs,update-dialog.ps1') "Only the Cập nhật dialog may install an update, found in: $($installers -join ', ')"
    $js=Get-Content -LiteralPath (Join-Path $root 'src/mac/ui/app.js') -Raw;$button=$js.IndexOf('go.onclick = async');$install=$js.IndexOf('fetch("/api/update"')
    Assert ([regex]::Matches($js,'/api/update').Count -eq 1 -and $button -ge 0 -and $install -gt $button -and $install - $button -lt 400) 'macOS installs only from the dialog button.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'PASS: updates replace app files and keep workspace and lessons; the check names the new version.'
