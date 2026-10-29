. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
. (Join-Path $root 'src/application/batch-import.ps1')
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('batch-import-'+[Guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Force -Path "$temp/img","$temp/project/workspace" | Out-Null
    $png=[byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A);$jpg=[byte[]](0xFF,0xD8,0xFF,0xE0)
    $make={param($Name,$Head,$Seed)[IO.File]::WriteAllBytes("$temp/img/$Name",[byte[]]($Head+[byte[]][Text.Encoding]::UTF8.GetBytes($Seed)));"$temp/img/$Name"}
    $p1=& $make 'p1.png' $png 'p1';$p2=& $make 'p2.jpg' $jpg 'p2';$r1=& $make 'r1.jpg' $jpg 'r1';$r2=& $make 'r2.png' $png 'r2';$r3=& $make 'r3.jpg' $jpg 'r3'
    $bad=& $make 'bad.jpg' ([byte[]](0x3C,0x68,0x74,0x6D)) 'html'

    # Plain links still work: one per line, nothing downloaded.
    $plain=ConvertFrom-ProductBatch "https://shop.test/a`n# note`nhttps://shop.test/b"
    Assert (@($plain.Rows).Count -eq 2 -and -not @($plain.Errors).Count -and -not $plain.Rows[0].Product) 'Plain links must parse as links without images.'

    # The table: one row per product image; two rows of one link give it two product images.
    $csv="product_url,product_image,review_images`nhttps://shop.test/a,$p1,$r1|$r2`nhttps://shop.test/a,$p2,$r3`nhttps://shop.test/b,,$r1"
    $parsed=ConvertFrom-ProductBatch $csv
    Assert (-not @($parsed.Errors).Count -and @($parsed.Rows).Count -eq 3 -and @($parsed.Rows[0].Reviews).Count -eq 2) 'The CSV table must parse.'
    $comma=ConvertFrom-ProductBatch "product_url,product_image,review_images`nhttps://shop.test/a,,`"https://cdn.test/r1.jpg,https://cdn.test/r2.jpg|https://cdn.test/r3.jpg`""
    Assert (-not @($comma.Errors).Count -and @($comma.Rows[0].Reviews).Count -eq 3) 'Review images may be separated by commas (quoted cell) as well as |.'
    $tsv=ConvertFrom-ProductBatch ("product_url`tproduct_image`treview_images`nhttps://shop.test/a`t$p1`t$r1")
    Assert (-not @($tsv.Errors).Count -and $tsv.Rows[0].Product -eq $p1) 'Rows pasted from a spreadsheet (tabs) must parse.'
    $wrong=ConvertFrom-ProductBatch "product_url,image`nnot-a-link,,x"
    Assert (@($wrong.Errors|Where-Object{$_ -match '^Dòng 1: cột lạ'}).Count -and @($wrong.Errors|Where-Object{$_ -match '^Dòng 2: link'}).Count) 'Problems must name their line.'

    $seen=@()
    $result=Import-ProductBatch "$temp/project" $parsed.Rows {param($Done,$Total)$script:seen+="$Done/$Total"}
    $map=Read-ManualReferenceMap "$temp/project/workspace/reference-inputs/references.json"
    $a=@(Get-ManualProducts @($map.entries|Where-Object product_url -eq 'https://shop.test/a')[0])
    Assert ($a.Count -eq 2 -and @($a[0].scenes).Count -eq 2 -and @($a[1].scenes).Count -eq 1) 'Each product image must get its own reviews.'
    Assert ($a[1].sha256 -eq (Get-BytesHash ([IO.File]::ReadAllBytes($p2))) -and $a[1].scenes[0].sha256 -eq (Get-BytesHash ([IO.File]::ReadAllBytes($r3)))) 'Reviews must stay with the product image of their row.'
    Assert (@(Get-ManualScenes @($map.entries|Where-Object product_url -eq 'https://shop.test/b')[0]).Count -eq 1) 'A row without a product image still adds its reviews.'
    Assert ($result.products -eq 2 -and $result.reviews -eq 4 -and -not @($result.failed).Count -and ($result.links -join ',') -eq 'https://shop.test/a,https://shop.test/b') 'The summary must count what was added.'
    Assert ($script:seen[-1] -eq '6/6') 'Progress must reach every image.'

    # A product image that is not a picture skips its row's reviews; a bad review is reported on its own.
    $broken=ConvertFrom-ProductBatch "product_url,product_image,review_images`nhttps://shop.test/c,$bad,$r1`nhttps://shop.test/d,$p1,$bad|$r2"
    $result=Import-ProductBatch "$temp/project" $broken.Rows $null
    $map=Read-ManualReferenceMap "$temp/project/workspace/reference-inputs/references.json"
    Assert (-not @($map.entries|Where-Object product_url -eq 'https://shop.test/c').Count) 'Reviews of a failed product image must not be attached elsewhere.'
    Assert (@($result.failed).Count -eq 2 -and $result.failed[0].line -eq 2 -and $result.failed[0].reason -match 'ảnh sản phẩm' -and $result.reviews -eq 1) 'Each failure must name its line and reason.'

    # The background script writes its result to the status file.
    $file="$temp/batch.csv";$status="$temp/status.json"
    [IO.File]::WriteAllText($file,"product_url,product_image,review_images`nhttps://shop.test/e,$p2,$r3")
    $copy="$temp/app";New-Item -ItemType Directory -Force -Path "$copy/workspace"|Out-Null;Copy-Item -Recurse (Join-Path $root 'src') "$copy/src"
    $shell=(Get-Command powershell.exe,pwsh -ErrorAction SilentlyContinue|Select-Object -First 1).Source
    & $shell -NoProfile -File "$copy/src/import-batch.ps1" -File $file -StatusFile $status 2>&1 | Write-Host
    $s=Get-Content $status -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($s.finished -and $s.products -eq 1 -and $s.reviews -eq 1 -and @($s.links)[0] -eq 'https://shop.test/e') 'The import script must report what it added.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'PASS: Nhập hàng loạt reads links or the table, attaches each row''s images to its product image and reports failures by line.'
