. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/infrastructure/csv.ps1')
$folder=Join-Path $TestWorkspaceRoot ('csv-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $folder|Out-Null
try{
    $path=Join-Path $folder 'loox.csv'
    $body="Wood, grain and `"curved`" legs.`nSecond line."
    $row=[pscustomobject]@{product_handle='table';rating=5;author='Test';email='';body=$body;created_at='2026-10-12 06:24:07 UTC';photo_url='https://example.test/photo.png';verified_purchase='true'}
    Save-Csv @($row) $path
    $bytes=[IO.File]::ReadAllBytes($path)
    if($bytes[0] -ne [byte][char]'p'){throw 'Loox header contains BOM or leading quotes.'}
    $header=Get-Content -LiteralPath $path -TotalCount 1 -Encoding UTF8
    if($header -cne 'product_handle,rating,author,email,body,created_at,photo_url,verified_purchase'){throw 'Header differs from Loox template.'}
    $saved=@(Import-Csv -LiteralPath $path -Encoding UTF8)
    if($saved.Count -ne 1 -or $saved[0].body -cne $body -or $saved[0].created_at -ne '2026-10-12' -or $saved[0].verified_purchase -cne 'TRUE'){throw 'CSV escaping or Loox value format failed.'}
    if($row.created_at -ne '2026-10-12 06:24:07 UTC' -or $row.verified_purchase -cne 'true'){throw 'Exporter mutated the source record.'}
    Save-Csv @() $path
    if([IO.File]::ReadAllText($path) -cne $header+"`r`n"){throw 'Empty export must retain the same plain header.'}
    Write-Host 'PASS: exact Loox header, no BOM, date/boolean format, CSV escaping and unchanged source data.'
}finally{
    $resolved=[IO.Path]::GetFullPath($folder);$allowed=[IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\')+'\'
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'csv-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
