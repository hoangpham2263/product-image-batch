. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
. (Join-Path $root 'src/application/support-logs.ps1')
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
# Gửi log carries what is needed to look into a problem, never the app password or images other than Bỏ samples.
$temp=Join-Path $TestWorkspaceRoot ('support-logs-'+[Guid]::NewGuid().ToString('N'))
try{
    $ws=Join-Path $temp 'workspace'
    foreach($d in @('logs','reference-inputs','output/2026-10-29_run/images','output/2026-10-29_run/refs/001-tee','output/2026-10-29_run/logs')){New-Item -ItemType Directory -Force -Path (Join-Path $ws $d)|Out-Null}
    '{"apiUrl":"https://api.test","adminKey":"never-send-this"}'|Set-Content -LiteralPath (Join-Path $ws 'drive.json') -Encoding UTF8
    'v9.9.9'|Set-Content -LiteralPath (Join-Path $ws 'version.txt')
    'https://example.test/products/tee'|Set-Content -LiteralPath (Join-Path $ws 'urls.txt') -Encoding UTF8
    '{"entries":[]}'|Set-Content -LiteralPath (Join-Path $ws 'reference-inputs/references.json') -Encoding UTF8
    try{throw 'nút bị lỗi'}catch{Write-AppError (Join-Path $ws 'logs') 'Giao diện Windows' $_}
    $big=Join-Path $ws 'logs/huge.log';$stream=[IO.File]::Create($big);try{$stream.SetLength(6MB)}finally{$stream.Dispose()}
    $run=Join-Path $ws 'output/2026-10-29_run'
    '[]'|Set-Content -LiteralPath (Join-Path $run 'results.json')
    'Lỗi tải ảnh'|Set-Content -LiteralPath (Join-Path $run 'logs/run.err.log') -Encoding UTF8
    '{"item_id":"001-tee"}'|Set-Content -LiteralPath (Join-Path $run 'refs/001-tee/manifest.json')
    foreach($image in @('images/001-tee.png','refs/001-tee/02-product.png')){New-TestPng (Join-Path $run $image) 2 2 ([byte[]](1,2,3))}
    $library=Join-Path $temp 'data/source-photos/Áo';New-Item -ItemType Directory -Force -Path $library|Out-Null
    foreach($n in 1..2){New-TestPng (Join-Path $library "a$n.png") 2 2 ([byte[]](1,2,3))}
    '{"a1.png":"m"}'|Set-Content -LiteralPath (Join-Path $library '.drive-sync.json')

    $bundle=New-SupportLogBundle $temp
    $out=Join-Path $temp 'unzipped';Expand-Archive -LiteralPath $bundle.Path -DestinationPath $out
    $top=@(Get-ChildItem -LiteralPath $out -Directory)[0].FullName
    foreach($file in @('summary.txt','app.json','tools.json','setup-check.json','config.json','queue/urls.txt','queue/references.json','logs/app-errors.log','runs/2026-10-29_run/results.json','runs/2026-10-29_run/logs/run.err.log','runs/2026-10-29_run/refs/001-tee/manifest.json')){
        Assert (Test-Path -LiteralPath (Join-Path $top $file)) "Gửi log is missing $file."
    }
    $all=@(Get-ChildItem -LiteralPath $out -File -Recurse)
    Assert (-not @($all|Where-Object{$_.Extension -eq '.png'}).Count) 'Gửi log must not carry images other than the Bỏ samples.'
    Assert (-not @($all|Where-Object{$_.Name -eq 'drive.json' -or (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'never-send-this'}).Count) 'The app password must never leave the machine.'
    Assert ((Get-Item -LiteralPath (Join-Path $top 'logs/huge.log')).Length -eq 2MB) 'A very large log keeps only its last 2 MB.'
    $config=Get-Content -LiteralPath (Join-Path $top 'config.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($config.app_password_saved -and $config.version_file -eq 'v9.9.9' -and $config.library[0].files -eq 2 -and $config.library[0].synced -eq 1) 'config.json must describe the setup without the password.'
    $app=Get-Content -LiteralPath (Join-Path $top 'app.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($app.install -eq 'zip' -and $app.version -eq 'v9.9.9' -and $app.os -and $app.powershell) 'app.json must describe the install and the system.'
    $errors=Get-Content -LiteralPath (Join-Path $top 'logs/app-errors.log') -Raw -Encoding UTF8
    Assert ($errors -match 'Giao diện Windows' -and $errors -match 'nút bị lỗi' -and $errors -match 'support-logs\.ps1') 'An error must be logged with where it happened.'
    $summary=Get-Content -LiteralPath (Join-Path $top 'summary.txt') -Raw -Encoding UTF8
    Assert ($summary -match 'v9\.9\.9' -and $summary -match '2026-10-29_run: 0 ảnh .* 1 dòng lỗi' -and $summary -match 'nút bị lỗi|Giao diện Windows') 'summary.txt must sum up the version, runs and latest errors.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'PASS: Gửi log carries system, tools, setup, config, queue, logs and runs, without the password or images.'
