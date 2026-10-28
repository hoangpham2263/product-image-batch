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
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'PASS: updates replace app files and keep workspace and lessons.'
