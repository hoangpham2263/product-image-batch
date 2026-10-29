. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('batch-review-'+[Guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path (Join-Path $temp 'images') -Force|Out-Null
    $rows=@(foreach($n in 1..3){
        $image=Join-Path $temp "images/00$n-tee.png";New-TestPng $image 1 1 ([byte[]](10,0,0))
        $refs=Join-Path $temp "refs/00$n-tee";New-Item -ItemType Directory -Path $refs -Force|Out-Null
        $original=Join-Path $refs 'product.png';New-TestPng $original 4 4 ([byte[]](0,100,0))
        New-TestPng (Join-Path $refs 'scene.png') 4 4 ([byte[]](0,0,100))
        Write-FeedbackJson (Join-Path $refs 'manifest.json') @{item_id="00$n-tee";product_url='https://example.test/products/tee';images=@(@{role='scene';file='scene.png'},@{role='product';file='product.png'})}
        [pscustomobject]@{product_handle='tee';rating='5';author='A';email='';body="b$n";created_at='2026-10-28';verified_purchase='true';photo_url="https://x.test/img/$n.png";photo_path=($image -replace '\\','/')}
    })
    Save-BatchResults $rows $temp
    $items=@(Get-BatchReview $temp)
    Assert ($items.Count -eq 3 -and -not $items[0].Decision) "Every result must be listed, undecided. Rows=$($rows.Count) Items=$($items.Count) Decision=$($items[0].Decision)"
    Assert ((Split-Path $items[0].ProductPath -Leaf) -eq 'product.png' -and (Split-Path $items[0].ScenePath -Leaf) -eq 'scene.png') 'Each result must know its product photo and the review photo it was made from.'
    $project=Join-Path $temp 'project';$rejected=Join-Path $project 'workspace/rejected'
    Set-BatchReviewDecision $temp '001-tee' ok $rejected
    Set-BatchReviewDecision $temp '002-tee' bad $rejected
    # A review marked Bỏ is noted with its text and reason, and goes out with the next Gửi lỗi.
    $sample=Join-Path $rejected ((Split-Path $temp -Leaf)+'__002-tee')
    Assert (@(Get-ChildItem -LiteralPath $sample -File).Name -join ',' -eq 'sample.json' -and (Get-Content -LiteralPath (Join-Path $sample 'sample.json') -Raw -Encoding UTF8|ConvertFrom-Json).body -eq 'b2') 'A rejected review is noted with its text only, no image copies.'
    Set-BatchReviewDecision $temp '002-tee' ok $rejected
    Assert (-not (Test-Path -LiteralPath $sample)) 'Changing a Bỏ before it is sent must drop the kept copy.'
    Set-BatchReviewDecision $temp '002-tee' bad $rejected -Reason ' sai màu áo '
    . (Join-Path $root 'src/application/support-logs.ps1')
    $bundle=New-SupportLogBundle $project
    try{
        Assert (@($bundle.Samples).Count -eq 1) 'Gửi lỗi must carry the rejected reviews not sent yet.'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip=[IO.Compression.ZipFile]::OpenRead($bundle.Path)
        try{
            Assert (-not @($zip.Entries|Where-Object{$_.FullName -like '*.png'}).Count) 'The error report carries no images.'
            $entry=@($zip.Entries|Where-Object{$_.FullName -like '*/report.json'})[0];$reader=New-Object IO.StreamReader($entry.Open())
            $report=try{$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
            Assert (@($report.rejected).Count -eq 1 -and $report.rejected[0].id -eq '002-tee' -and $report.rejected[0].reason -eq 'sai màu áo') 'The report must list the Bỏ review with the reason typed.'
        }finally{$zip.Dispose()}
    }finally{Remove-Item -LiteralPath $bundle.Path -Force -ErrorAction SilentlyContinue}
    Complete-RejectedSamples $bundle.Samples
    Assert (-not @(Get-UnsentRejectedSamples $project).Count) 'Samples sent once must not be sent again.'
    Set-BatchReviewDecision $temp '002-tee' bad $rejected
    Assert (-not (Test-Path (Join-Path $temp 'loox_import.csv'))) 'No Loox file may exist before the review is done.'
    $failed=$false;try{Export-ReviewedCsv $temp|Out-Null}catch{$failed=$_.Exception.Message -match 'chưa duyệt'}
    Assert $failed 'The final file must wait until every image is checked.'
    Set-BatchReviewDecision $temp '003-tee' ok $rejected
    Set-BatchReviewDecision $temp '003-tee' '' $rejected
    Assert (-not @(Get-BatchReview $temp)[2].Decision) 'Clicking a decision again must clear it.'
    Set-BatchReviewDecision $temp '003-tee' ok $rejected
    $exported=Export-ReviewedCsv $temp
    Assert ((Split-Path $exported -Leaf) -eq 'loox_import.csv' -and -not (Test-Path (Join-Path $temp 'loox_import_final.csv'))) 'The reviewed export is the one Loox file.'
    $csv=@(Import-Csv $exported)
    Assert ($csv.Count -eq 2 -and ($csv.body -join ',') -eq 'b1,b3' -and @($csv|Where-Object product_handle -eq 'tee').Count -eq 2) 'Rejecting one review removed other reviews of the same product.'
    if($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows){
        Add-Type -AssemblyName System.Windows.Forms
        . (Join-Path $root 'src/ui/image-feedback.ps1')
        . (Join-Path $root 'src/ui/manual-references.ps1')
        . (Join-Path $root 'src/ui/batch-review.ps1')
        foreach($item in @(Get-BatchReview $temp)){Set-BatchReviewDecision $temp $item.Id ''}
        $view=New-BatchReviewDialog (Split-Path $temp -Parent) $temp
        $script:Preview=$null
        function Show-BatchReviewPreview($View,$Item,$Decide){$script:Preview=New-BatchReviewPreview $View $Item $Decide}
        try{
            $view.Form.ShowInTaskbar=$false;$view.Form.StartPosition='Manual';$view.Form.Location=[Drawing.Point]::new(-32000,-32000);$view.Form.Show();$view.Form.Refresh()
            Assert ($view.List.Controls.Count -eq 3 -and @($view.List.Controls|Where-Object Height -gt 100).Count -eq 0) 'Reviews must be compact individual rows.'
            foreach($row in $view.List.Controls){Assert (@($row.Controls|Where-Object{$_ -is [Windows.Forms.PictureBox]}).Count -eq 1) 'Product comparison image must not be listed as another review.'}
            $view.List.Controls[0].Controls.Find('KeepReview',$true)[0].PerformClick()
            $view.List.Controls[1].Controls.Find('SkipReview',$true)[0].PerformClick()
            $items=@(Get-BatchReview $temp)
            Assert ($items[0].Decision -eq 'ok' -and $items[1].Decision -eq 'bad' -and -not $items[2].Decision) 'Row buttons affected another review of the same product.'
            $thumbnail=$view.List.Controls[2].Controls.Find('ReviewThumbnail',$true)[0]
            $click=[Windows.Forms.Control].GetMethod('OnClick',[Reflection.BindingFlags]'NonPublic,Instance')
            [void]$click.Invoke($thumbnail,@([EventArgs]::Empty))
            Assert ($script:Preview -and $script:Preview.Tag.Id -eq '003-tee') 'Thumbnail did not open the matching review preview.'
            $script:Preview.ShowInTaskbar=$false;$script:Preview.StartPosition='Manual';$script:Preview.Location=[Drawing.Point]::new(-32000,-32000);$script:Preview.Show();$script:Preview.Refresh()
            Assert ($script:Preview.Controls.Find('OriginalProductPreview',$true)[0].Image -and $script:Preview.Controls.Find('OriginalReviewPreview',$true)[0].Image -and $script:Preview.Controls.Find('ReviewImagePreview',$true)[0].Image) 'Preview must show the product photo, the original review photo and the result.'
            Assert (-not @($script:Preview.Controls|Where-Object{$_ -is [Windows.Forms.Button] -and $_.Text -eq 'Đóng'}).Count) 'The preview closes through Giữ or Bỏ; it has no Đóng button.'
            $bitmap=[Drawing.Bitmap]::new($script:Preview.Width,$script:Preview.Height)
            try{$script:Preview.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height));$bitmap.Save((Join-Path $TestWorkspaceRoot 'batch-review-preview.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
            $script:Preview.Controls.Find('KeepPreviewReview',$true)[0].PerformClick()
            Assert ($script:Preview.IsDisposed -or -not $script:Preview.Visible) 'Giữ in the preview must close it.'
            Assert ($view.Items[2].Decision -eq 'ok' -and $view.Items[1].Decision -eq 'bad' -and $view.Form.Controls.Find('ExportReviews',$true)[0].Enabled) 'Preview selection did not synchronize with its row and export readiness.'
            $csv=@(Import-Csv (Export-ReviewedCsv $temp))
            Assert (($csv.body -join ',') -eq 'b1,b3') 'Final export did not preserve the kept review of a partially rejected product.'
            foreach($pair in @(,@($view.Form,'batch-review-list.png'))){
                $window=$pair[0];$bitmap=[Drawing.Bitmap]::new($window.Width,$window.Height)
                try{$window.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height));$bitmap.Save((Join-Path $TestWorkspaceRoot $pair[1]),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
            }
            $reopened=New-BatchReviewDialog (Split-Path $temp -Parent) $temp
            try{Assert (($reopened.Items.Decision -join ',') -eq 'ok,bad,ok') 'Per-review decisions were not restored on reopening.'}finally{$reopened.Form.Dispose()}
        }finally{if($script:Preview){$script:Preview.Dispose()};$view.Form.Dispose()}
    }
}finally{
    Get-ChildItem -LiteralPath (Join-Path (Split-Path (Split-Path ([IO.Path]::GetFullPath($temp)) -Parent) -Parent) 'rejected') -Directory -Filter ((Split-Path $temp -Leaf)+'__*') -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force
    $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\')+'\'
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'batch-review-*'){Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
}
Write-Host 'PASS: every result is checked before the final CSV, which keeps only accepted images.'
