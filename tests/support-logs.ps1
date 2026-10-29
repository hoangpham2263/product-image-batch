. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
. (Join-Path $root 'src/application/support-logs.ps1')
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
# Gửi lỗi sends one small error report, never the app password or images.
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

    # Long names (reproduces "Chưa tạo được file log" on Windows without long paths): an item id long enough that the
    # old staged copy, temp + prb-log-<guid> + bundle name + runs/<run>/refs/<item>/manifest.json, passes 260 characters,
    # while the source itself stays under 260 so the fixture can exist on Windows PowerShell 5.1.
    $refs=Join-Path $run 'refs'
    $itemLength=[Math]::Min(200, 250 - ([IO.Path]::GetFullPath($refs).Length + '/manifest.json'.Length + 1))
    $longItem='001-'+('ban-go-tu-nhien-chan-tang-nguyen-khoi-' * 10).Substring(0, $itemLength - 4)
    New-Item -ItemType Directory -Force -Path (Join-Path $refs $longItem)|Out-Null
    '{"item_id":"long"}'|Set-Content -LiteralPath (Join-Path $refs "$longItem/manifest.json")
    $bundleName="2026-10-29_000000_v9.9.9_windows_$([Environment]::MachineName -replace '[^\w-]', '')"
    $oldStaged=([IO.Path]::GetTempPath() + 'prb-log-' + [Guid]::NewGuid().ToString('N') + "/$bundleName/runs/2026-10-29_run/refs/$longItem/manifest.json").Length
    Assert ($oldStaged -gt 260) "The fixture must need a path over 260 characters the old way (got $oldStaged)."
    $tempBefore=@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'prb-log-*' -ErrorAction SilentlyContinue).Count

    $bundle=New-SupportLogBundle $temp
    $tempAfter=@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'prb-log-*' -ErrorAction SilentlyContinue).Count
    Assert ($tempAfter -le $tempBefore) 'Gửi lỗi must not stage files in a temp folder.'
    Assert ((Test-Path -LiteralPath $bundle.Path) -and (Split-Path $bundle.Path -Parent) -eq (Join-Path $ws 'temp')) 'The ZIP stays in workspace/temp, ready to send by hand if the upload fails.'
    # Read the ZIP in memory: extracting it would itself hit the 260-character limit on Windows.
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($bundle.Path)
    try{
        $entries=@{}
        foreach($e in $zip.Entries){
            $relative=($e.FullName -replace '\\','/') -replace '^[^/]+/',''
            $reader=New-Object IO.StreamReader($e.Open(),[Text.Encoding]::UTF8)
            try{$entries[$relative]=[pscustomobject]@{Length=$e.Length;Text=$(if($e.Length -lt 1MB){$reader.ReadToEnd()}else{''})}}finally{$reader.Dispose()}
        }
    }finally{$zip.Dispose()}
    Assert (@($entries.Keys).Count -eq 2 -and $entries.ContainsKey('report.json') -and $entries.ContainsKey('summary.txt')) "Gửi lỗi is one error report: report.json and summary.txt (got $(@($entries.Keys) -join ', '))."
    Assert ((Get-Item -LiteralPath $bundle.Path).Length -lt 200KB) 'The error report must stay small.'
    Assert (-not @($entries.Keys|Where-Object{$entries[$_].Text -match 'never-send-this'}).Count) 'The app password must never leave the machine.'
    $report=$entries['report.json'].Text|ConvertFrom-Json
    Assert ($report.format -eq 'prb-error-report/1' -and $report.app.version -eq 'v9.9.9' -and $report.app.install -eq 'zip' -and $report.config.app_password_saved) 'report.json must describe the app and setup without the password.'
    $sources=@($report.errors|ForEach-Object source)
    Assert ('logs/app-errors.log' -in $sources -and (@($report.errors|Where-Object source -eq 'logs/app-errors.log')[0].text -match 'nút bị lỗi')) 'App errors must be in the report.'
    Assert ('runs/2026-10-29_run/logs/run.err.log' -in $sources -and 'logs/huge.log' -notin $sources) 'Only error lines go in: the run error, not a log without errors.'
    $summary=$entries['summary.txt'].Text
    Assert ($summary -match 'v9\.9\.9' -and $summary -match 'nút bị lỗi|Giao diện Windows' -and $summary -match 'nguồn có lỗi') 'summary.txt must sum up the version, runs and errors.'
    # After a sent report the next one starts from then: nothing old is reported again.
    Complete-SupportLogSend $temp
    Remove-Item -LiteralPath $bundle.Path -Force
    $next=New-SupportLogBundle $temp
    $zip=[IO.Compression.ZipFile]::OpenRead($next.Path)
    try{$reader=New-Object IO.StreamReader(@($zip.Entries|Where-Object{$_.FullName -like '*/report.json'})[0].Open());$again=try{$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}}finally{$zip.Dispose()}
    Assert ([datetime]$again.since -gt (Get-Date).AddHours(-2)) 'The next report must start from the last one sent.'
    $bundle=$next
    Remove-Item -LiteralPath $bundle.Path -Force
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'PASS: Gửi lỗi is one small error report (report.json + summary.txt) since the last one, without the password or images.'
