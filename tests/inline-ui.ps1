. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
. (Join-Path $project 'src/ui/main-window.ps1') -BuildOnly
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
Assert ($animTimer -is [Windows.Forms.Timer]) 'Run animation timer was not initialized.'
$animTimer.Start()
Assert $animTimer.Enabled 'Run animation timer could not start.'
$animTimer.Stop()
$testFolder=Join-Path $TestWorkspaceRoot ('inline-main-'+[Guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $testFolder -Force|Out-Null
    $queueEditor.Root=$testFolder;$queueEditor.MapPath=Join-Path $testFolder 'workspace/reference-inputs/references.json'
    $url='https://bangometay.com/p/ban-go-tu-nhien-chan-tang-nguyen-khoi-tu-nhien-2m8x85x6-5cm/'
    Set-ProductQueueUrls $queueEditor @($url,'https://example.test/products/coffee-table')
    $room=Join-Path $project 'data/source-photos/Nội thất/dining-tables-dutch-012.jpg'
    Set-ProductQueueReference $queueEditor $queueEditor.Rows[0] $room
    $form.ShowInTaskbar=$false;$form.StartPosition='Manual';$form.Location=[Drawing.Point]::new(-32000,-32000)
    $form.Show();$form.Refresh()
    Assert ($queueEditor.Rows.Count -eq 2 -and $queueEditor.Rows[0].Preview.Image -and -not $queueEditor.Rows[1].Preview.Image) 'Main screen lost link/image pairing or missing-reference state.'
    Assert ($queueEditor.Rows[0].Card.Height -le 64 -and $queueEditor.Rows[0].Url.ReadOnly) 'Main queue must use compact rows.'
    $before=[IO.File]::ReadAllText($queueEditor.MapPath)
    $popup=New-ProductQueueDialog $queueEditor $queueEditor.Rows[0]
    try{
        $draft=$popup.Tag
        $groups=$popup.Controls.Find('SourcePhotoGroup',$true)[0]
        Assert ($groups.Items.Contains('Áo') -and $groups.Items.Contains('Nội thất')) 'Photo groups are missing.'
        $groups.SelectedItem='Nội thất'
        Assert ($draft.Editor.SourceGroup -eq 'Nội thất') 'Group selection did not update the draft picker.'
        Assert ($draft.Url.Text -eq $url -and @($draft.Products).Count -eq 1) 'Opening a row must show the matching URL and its images.'
        $draft.Url.Text='https://example.test/products/cancelled'
        Assert (-not @($draft.Products).Count) 'Changed URL retained the old images.'
        # Two product images, each with its own reviews.
        Add-ProductDraftImages $draft @($room) -1
        Add-ProductDraftImages $draft @($room) 0
        $second=Join-Path $testFolder 'second.png';$bitmap=[Drawing.Bitmap]::new(8,8);try{$bitmap.Save($second,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
        Add-ProductDraftImages $draft @($second) -1
        Add-ProductDraftImages $draft @($room,$second) 1
        Assert (@($draft.Products).Count -eq 2 -and @($draft.Products[1].scenes).Count -eq 2 -and $draft.Rows.Controls.Count -eq 3) 'Each product image must keep its own review images in its own row.'
    }finally{$popup.Dispose()}
    Assert ($queueEditor.Rows[0].Url.Text -eq $url -and [IO.File]::ReadAllText($queueEditor.MapPath) -eq $before) 'Cancelling a popup changed the actual URL or map.'
    $popup=New-ProductQueueDialog $queueEditor
    try{
        $draft=$popup.Tag;$draft.Url.Text=$url
        $popup.Controls.Find('SourcePhotoGroup',$true)[0].SelectedItem='Nội thất'
        $blocked=$false;try{Save-ProductQueueDraft $queueEditor $draft}catch{$blocked=$true}
        Assert $blocked 'Popup accepted a duplicate URL.'
        $draft.Url.Text='https://example.test/products/new'
        Add-ProductDraftImages $draft @($room) -1
        Add-ProductDraftImages $draft @($room) 0
        Save-ProductQueueDraft $queueEditor $draft
    }finally{$popup.Dispose()}
    Assert ($queueEditor.Rows.Count -eq 3 -and (Test-Path -LiteralPath $queueEditor.Rows[2].ImagePath)) 'Saving a new popup did not preserve its snapshot after cleanup.'
    $pair=@((Read-ManualReferenceMap $queueEditor.MapPath).entries|Where-Object product_url -eq 'https://example.test/products/new')[0]
    Assert ((Test-Path $pair.product_file) -and (Test-Path $pair.file) -and $pair.product_file -ne $pair.file) 'Saving a popup lost one of the two input snapshots.'
    Assert ($queueEditor.SourceGroup -eq 'Nội thất' -and (Read-ManualReferenceMap $queueEditor.MapPath).preferred_source_group -eq 'Nội thất') 'Saved group preference was lost.'
    $popup=New-ProductQueueDialog $queueEditor $queueEditor.Rows[2]
    try{
        $popup.StartPosition='Manual';$popup.Location=[Drawing.Point]::new(-32000,-32000);$popup.Show();$popup.Refresh()
        $thumbs=@($popup.Tag.Rows.Controls[0].Controls|Where-Object{$_ -is [Windows.Forms.PictureBox]})
        Assert ($thumbs.Count -eq 2 -and $thumbs[0].Width -le 64) 'Popup rows must show small product and review thumbnails.'
        $bitmap=[Drawing.Bitmap]::new($popup.Width,$popup.Height)
        try{$popup.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height));$bitmap.Save((Join-Path $TestWorkspaceRoot 'product-popup-preview.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    }finally{$popup.Dispose()}
    Add-ProductQueueLinks $queueEditor ((4..100|ForEach-Object{"https://example.test/products/item-$_"}) -join "`n")
    Assert ($queueEditor.Rows.Count -eq 100 -and $queueEditor.Flow.AutoScroll) 'Large queues lost products or scrolling.'
    $queueEditor.Flow.ScrollControlIntoView($queueEditor.Rows[0].Card);$form.Refresh()
    $screenshot=Join-Path $TestWorkspaceRoot 'main-inline-preview.png'
    $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
    try{$form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height));$bitmap.Save($screenshot,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    $form.Size=$form.MinimumSize;$queueEditor.Fallback.Checked=$true;$form.Refresh()
    Assert ($lblStatus.Right -lt $lblPer.Left -and -not $lblProgress.Bounds.IntersectsWith($btnDrive.Bounds)) 'Controls overlap at the minimum window size.'
    $sidebar=@($btnSave,$btnOut,$btnReview,$btnSetup,$btnDrive)
    $queueRight=$queueEditor.Panel.PointToScreen([Drawing.Point]::new($queueEditor.Panel.Width,0)).X
    Assert (@($sidebar|Where-Object {$_.PointToScreen([Drawing.Point]::Empty).X -lt $queueRight -or $_.Width -ne $btnSave.Width}).Count -eq 0) 'Action buttons must form a separate right column.'
    for($i=1;$i -lt $sidebar.Count;$i++){Assert ($sidebar[$i].Top -gt $sidebar[$i-1].Bottom) 'Right-column buttons overlap.'}
    $queueEditor.Panel.Enabled=$false
    Assert (-not $queueEditor.Rows[0].Url.Enabled -and -not $queueEditor.Rows[0].Card.Controls.Find('PreviewProduct',$true)[0].Enabled) 'Running-state lock left row inputs editable.'
    Write-Host 'PASS: compact 100-product queue, popup preview, save/cancel isolation, duplicate checks, snapshots, layout and run lock.' -ForegroundColor Green
}finally{
    $form.Dispose()
    $resolved=[IO.Path]::GetFullPath($testFolder);$allowed=[IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\')+'\'
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'inline-main-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
