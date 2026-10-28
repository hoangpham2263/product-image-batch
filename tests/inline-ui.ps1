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
        Assert ($groups.Items.Contains('Áo') -and $groups.Items.Contains('Nội thất')) 'Local photo groups are missing.'
        $groups.SelectedItem='Nội thất'
        Assert ($draft.Editor.SourceGroup -eq 'Nội thất') 'Group selection did not update the draft picker.'
        Assert ($draft.Row.Url.Text -eq $url -and $draft.Row.Preview.Image) 'Clicking a row must preview the matching URL and image.'
        $draft.Row.Url.Text='https://example.test/products/cancelled'
        Assert (-not $draft.Row.Preview.Image) 'Changed URL retained the old reference.'
        Set-ProductQueueReference $draft.Editor $draft.Row $room
        [void](Save-ManualReference $draft.Editor.Root $draft.Row.Url.Text $room Product)
        $draft.Row.BoundUrl=$null;Update-ProductQueueRow $draft.Editor $draft.Row
        Assert ($draft.Row.ProductPreview.Image) 'Product preview did not load independently.'
    }finally{$popup.Dispose()}
    Assert ($queueEditor.Rows[0].Url.Text -eq $url -and [IO.File]::ReadAllText($queueEditor.MapPath) -eq $before) 'Cancelling a popup changed the actual URL or map.'
    $popup=New-ProductQueueDialog $queueEditor
    try{
        $draft=$popup.Tag;$draft.Row.Url.Text=$url
        $popup.Controls.Find('SourcePhotoGroup',$true)[0].SelectedItem='Nội thất'
        $blocked=$false;try{Save-ProductQueueDraft $queueEditor $draft}catch{$blocked=$true}
        Assert $blocked 'Popup accepted a duplicate URL.'
        $draft.Row.Url.Text='https://example.test/products/new'
        Set-ProductQueueReference $draft.Editor $draft.Row $room
        [void](Save-ManualReference $draft.Editor.Root $draft.Row.Url.Text $room Product)
        Save-ProductQueueDraft $queueEditor $draft
    }finally{$popup.Dispose()}
    Assert ($queueEditor.Rows.Count -eq 3 -and (Test-Path -LiteralPath $queueEditor.Rows[2].ImagePath)) 'Saving a new popup did not preserve its snapshot after cleanup.'
    $pair=@((Read-ManualReferenceMap $queueEditor.MapPath).entries|Where-Object product_url -eq 'https://example.test/products/new')[0]
    Assert ((Test-Path $pair.product_file) -and (Test-Path $pair.file) -and $pair.product_file -ne $pair.file) 'Saving a popup lost one of the two input snapshots.'
    Assert ($queueEditor.SourceGroup -eq 'Nội thất' -and (Read-ManualReferenceMap $queueEditor.MapPath).preferred_source_group -eq 'Nội thất') 'Saved group preference was lost.'
    $popup=New-ProductQueueDialog $queueEditor $queueEditor.Rows[0]
    try{
        $popup.StartPosition='Manual';$popup.Location=[Drawing.Point]::new(-32000,-32000);$popup.Show();$popup.Refresh()
        Assert ($popup.Tag.Row.Preview.Width -gt 600 -and $popup.Tag.Row.Preview.Height -gt 250) 'Popup preview is too small.'
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
    Assert ($lblStatus.Right -lt $lblPer.Left -and -not $lblProgress.Bounds.IntersectsWith($btnClear.Bounds)) 'Controls overlap at the minimum window size.'
    $sidebar=@($btnSave,$btnOut,$btnFeedback,$btnSetup,$btnHelp,$btnClear)
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
