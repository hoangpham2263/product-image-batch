# One compact row per review; product photos are comparison material in the preview.
function New-BatchReviewPreview($View,$Item,$Decide) {
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Xem ảnh đánh giá';ClientSize='1080,720';MinimumSize='860,560';StartPosition='CenterParent';Font=(New-Object Drawing.Font('Segoe UI',10));Tag=$Item}
    $pictures=New-Object Windows.Forms.TableLayoutPanel -Property @{Location='12,42';Size='1056,530';Anchor='Top,Bottom,Left,Right';ColumnCount=2;RowCount=1}
    [void]$pictures.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',50)))
    [void]$pictures.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',50)))
    $originalLabel=New-Object Windows.Forms.Label -Property @{Text='Ảnh sản phẩm gốc · chỉ để đối chiếu';Location='12,12';Size='500,24'}
    $resultLabel=New-Object Windows.Forms.Label -Property @{Text='Ảnh của đánh giá đang chọn';Location='548,12';Size='500,24';Anchor='Top,Right'}
    $product=New-Object Windows.Forms.PictureBox -Property @{Name='OriginalProductPreview';Dock='Fill';SizeMode='Zoom';BackColor=[Drawing.Color]::WhiteSmoke;Margin='0,0,6,0'}
    $result=New-Object Windows.Forms.PictureBox -Property @{Name='ReviewImagePreview';Dock='Fill';SizeMode='Zoom';BackColor=[Drawing.Color]::WhiteSmoke;Margin='6,0,0,0'}
    try{Set-FeedbackPreview $product $Item.ProductPath;Set-FeedbackPreview $result $Item.ImagePath}catch{Set-FeedbackPreview $product '';Set-FeedbackPreview $result '';$dialog.Dispose();throw}
    if(-not $product.Image){$originalLabel.Text='Ảnh sản phẩm gốc · không có ảnh đối chiếu'}
    $pictures.Controls.Add($product,0,0);$pictures.Controls.Add($result,1,0)
    $body=New-Object Windows.Forms.TextBox -Property @{Text=[string]$Item.Row.body;Location='12,584';Size='1056,70';Multiline=$true;ReadOnly=$true;ScrollBars='Vertical';Anchor='Bottom,Left,Right'}
    $state=New-Object Windows.Forms.Label -Property @{Name='PreviewDecision';Location='12,674';Size='540,28';Anchor='Bottom,Left'}
    $keep=New-Object Windows.Forms.Button -Property @{Name='KeepPreviewReview';Text='Giữ đánh giá';Location='648,670';Size='130,36';Anchor='Bottom,Right'}
    $skip=New-Object Windows.Forms.Button -Property @{Name='SkipPreviewReview';Text='Bỏ đánh giá';Location='790,670';Size='130,36';Anchor='Bottom,Right'}
    $close=New-Object Windows.Forms.Button -Property @{Text='Đóng';Location='932,670';Size='136,36';Anchor='Bottom,Right';DialogResult='Cancel'}
    $refresh={
        $state.Text=switch($Item.Decision){'ok'{'Đang giữ đánh giá này'}'bad'{'Đang bỏ đánh giá này khỏi CSV'}default{'Chưa chọn giữ hoặc bỏ'}}
    }.GetNewClosure()
    $keep.Add_Click({& $Decide 'ok';& $refresh}.GetNewClosure());$skip.Add_Click({& $Decide 'bad';& $refresh}.GetNewClosure())
    $dialog.Controls.AddRange(@($originalLabel,$resultLabel,$pictures,$body,$state,$keep,$skip,$close));$dialog.CancelButton=$close
    $dialog.Add_Disposed({Set-FeedbackPreview $product '';Set-FeedbackPreview $result ''}.GetNewClosure())
    & $refresh
    return $dialog
}

function Show-BatchReviewPreview($View,$Item,$Decide) {
    $preview=New-BatchReviewPreview $View $Item $Decide
    try{[void]$preview.ShowDialog($View.Form)}finally{$preview.Dispose()}
}

function New-BatchReviewRow($View,$Item,[int]$Number=1) {
    $ui=$script:Ui
    $width=[Math]::Max(840,$View.List.ClientSize.Width-28)
    $row=New-Object Windows.Forms.Panel -Property @{Name='ReviewRow';Size=(New-Object Drawing.Size($width,64));Margin='0,0,0,3';BackColor=$ui.Surface;BorderStyle='FixedSingle';Tag=$Item}
    $result=New-Object Windows.Forms.PictureBox -Property @{Name='ReviewThumbnail';Location='8,7';Size='48,48';SizeMode='Zoom';BackColor=[Drawing.Color]::WhiteSmoke;Cursor='Hand';Tag=$Item.ImagePath}
    if(Test-Path -LiteralPath $Item.ImagePath){$result.Image=New-ThumbnailImage $Item.ImagePath 48}
    $title=New-Object Windows.Forms.Label -Property @{Text=("#$Number · "+$Item.Row.product_handle);Location='68,5';Size=(New-Object Drawing.Size(($width-240),20));Anchor='Top,Left,Right';AutoEllipsis=$true}
    $body=New-Object Windows.Forms.Label -Property @{Name='ReviewBody';Text=[string]$Item.Row.body;Location='68,28';Size=(New-Object Drawing.Size(($width-240),24));Anchor='Top,Left,Right';AutoEllipsis=$true;ForeColor=$ui.Muted}
    $ok=New-Object Windows.Forms.Button -Property @{Name='KeepReview';Text='Giữ';Location=(New-Object Drawing.Point(($width-152),17));Size='64,28';Anchor='Top,Right'}
    $bad=New-Object Windows.Forms.Button -Property @{Name='SkipReview';Text='Bỏ';Location=(New-Object Drawing.Point(($width-80),17));Size='64,28';Anchor='Top,Right'}
    $paint={
        foreach($button in @($ok,$bad)){$button.FlatStyle='Standard';$button.UseVisualStyleBackColor=$true;$button.ForeColor=$ui.Ink}
        if($Item.Decision -eq 'ok'){$ok.FlatStyle='Flat';$ok.BackColor=$ui.Accent;$ok.ForeColor=[Drawing.Color]::White;$row.BackColor=[Drawing.Color]::FromArgb(236,246,239)}
        elseif($Item.Decision -eq 'bad'){$bad.FlatStyle='Flat';$bad.BackColor=$ui.Error;$bad.ForeColor=[Drawing.Color]::White;$row.BackColor=[Drawing.Color]::FromArgb(250,236,236)}
        else{$row.BackColor=$ui.Surface}
        $row.AccessibleDescription=switch($Item.Decision){'ok'{'Giữ đánh giá này'}'bad'{'Bỏ riêng đánh giá này'}default{'Chưa chọn'}}
    }.GetNewClosure()
    $decide={param($value)
        $next=if($Item.Decision -eq $value){''}else{$value}
        Set-BatchReviewDecision $View.BatchDir $Item.Id $next
        $Item.Decision=$next;& $paint;& $View.Refresh
    }.GetNewClosure()
    $ok.Add_Click({& $decide 'ok'}.GetNewClosure());$bad.Add_Click({& $decide 'bad'}.GetNewClosure())
    $result.Add_Click({Show-BatchReviewPreview $View $Item $decide}.GetNewClosure())
    & $paint
    $row.Controls.AddRange(@($result,$title,$body,$ok,$bad))
    return $row
}

function Clear-BatchReviewRows($List) {
    foreach($row in @($List.Controls)){
        foreach($picture in @($row.Controls|Where-Object{$_ -is [Windows.Forms.PictureBox]})){Set-FeedbackPreview $picture ''}
        $row.Dispose()
    }
    $List.Controls.Clear()
}

function New-BatchReviewDialog([string]$OutputRoot,[string]$BatchDir='') {
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Duyệt kết quả';Size='940,760';MinimumSize='940,500';StartPosition='CenterParent';Font=(New-Object Drawing.Font('Segoe UI',10))}
    $batches=New-Object Windows.Forms.ComboBox -Property @{Location='12,12';Size='600,28';DropDownStyle='DropDownList';DisplayMember='Label';Anchor='Top,Left'}
    $hint=New-Object Windows.Forms.Label -Property @{Text='Mỗi dòng một đánh giá. Bấm ảnh để xem lớn; Giữ/Bỏ chỉ áp dụng cho dòng đó.';Location='12,46';Size='900,22';ForeColor=$script:Ui.Muted}
    $flow=New-Object Windows.Forms.FlowLayoutPanel -Property @{Name='ReviewList';Location='12,72';Size='900,580';AutoScroll=$true;FlowDirection='TopDown';WrapContents=$false;Anchor='Top,Bottom,Left,Right'}
    $status=New-Object Windows.Forms.Label -Property @{Name='ReviewSummary';Location='12,668';Size='560,36';TextAlign='MiddleLeft';Anchor='Bottom,Left'}
    $export=New-Object Windows.Forms.Button -Property @{Name='ExportReviews';Text='Xuất file Loox';Location='732,664';Size='180,40';Anchor='Bottom,Right'}
    Set-FlatButton $export -Primary
    $dialog.Controls.AddRange(@($batches,$hint,$flow,$status,$export))
    $view=[pscustomobject]@{Form=$dialog;BatchDir='';Items=@();Refresh=$null;List=$flow}
    $view.Refresh={
        $items=@($view.Items);$done=@($items|Where-Object Decision).Count;$good=@($items|Where-Object Decision -eq 'ok').Count
        $status.Text="Đã duyệt $done/$($items.Count) đánh giá • Giữ $good • Bỏ $($done-$good)"
        $export.Enabled=$items.Count -gt 0 -and $done -eq $items.Count -and $good -gt 0
    }.GetNewClosure()
    $load={
        Clear-BatchReviewRows $flow
        if(-not $batches.SelectedItem){$view.Items=@();& $view.Refresh;return}
        $view.BatchDir=$batches.SelectedItem.Path
        $view.Items=@(Get-BatchReview $view.BatchDir)
        $flow.SuspendLayout()
        $number=0
        foreach($item in $view.Items){$number++;$flow.Controls.Add((New-BatchReviewRow $view $item $number))}
        $flow.ResumeLayout()
        & $view.Refresh
    }.GetNewClosure()
    $batches.Add_SelectedIndexChanged($load)
    $flow.Add_ClientSizeChanged({foreach($row in @($flow.Controls)){$row.Width=[Math]::Max(840,$flow.ClientSize.Width-28)}}.GetNewClosure())
    $dialog.Add_Disposed({Clear-BatchReviewRows $flow}.GetNewClosure())
    # Export shows its progress on the button itself; no extra message windows.
    $exportReset=New-Object Windows.Forms.Timer -Property @{Interval=2000}
    $exportReset.Add_Tick({$exportReset.Stop();$export.Text='Xuất file Loox';& $view.Refresh}.GetNewClosure())
    $export.Add_Click({
        $export.Enabled=$false;$export.Text='Đang xuất…';$dialog.Cursor='WaitCursor';$dialog.Refresh()
        try{
            [void](Export-ReviewedCsv $view.BatchDir)
            $export.Text='✓ Đã xuất'
            $item=$batches.SelectedItem;if($item -and $item.Label -notlike '*đã xuất'){$item.Label+='  • đã xuất';$batches.Items[$batches.SelectedIndex]=$item}
            $exportReset.Start()
        }catch{$status.Text=$_.Exception.Message;$export.Text='Xuất file Loox';& $view.Refresh}
        finally{$dialog.Cursor='Default'}
    }.GetNewClosure())
    $dialog.Add_Disposed({$exportReset.Dispose()}.GetNewClosure())
    if(Test-Path -LiteralPath $OutputRoot){
        foreach($dir in @(Get-ChildItem -LiteralPath $OutputRoot -Directory|Where-Object{Test-Path -LiteralPath (Join-Path $_.FullName 'results.json')}|Sort-Object Name -Descending|Select-Object -First 30)){
            $label=$dir.Name+$(if(Test-Path -LiteralPath (Join-Path $dir.FullName 'loox_import.csv')){'  • đã xuất'}else{''})
            $index=$batches.Items.Add([pscustomobject]@{Label=$label;Path=$dir.FullName})
            if($BatchDir -and $dir.FullName -eq (Get-Item -LiteralPath $BatchDir -ErrorAction SilentlyContinue).FullName){$batches.SelectedIndex=$index}
        }
        if($batches.Items.Count -and $batches.SelectedIndex -lt 0){$batches.SelectedIndex=0}
    }
    if(-not $batches.Items.Count){$status.Text='Chưa có lần chạy nào để duyệt. Lần chạy tạo ra ảnh sẽ hiện ở đây.'}
    else{& $view.Refresh}
    return $view
}

function Show-BatchReviewDialog($Owner,[string]$OutputRoot,[string]$BatchDir='') {
    $view=New-BatchReviewDialog $OutputRoot $BatchDir
    try{[void]$view.Form.ShowDialog($Owner)}finally{$view.Form.Dispose()}
}
