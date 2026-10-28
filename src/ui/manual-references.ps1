# Inline product cards keep the URL and its chosen reference together.
$script:Ui=@{
    Ink=[Drawing.Color]::FromArgb(30,30,30); Muted=[Drawing.Color]::FromArgb(96,96,96); Line=[Drawing.Color]::FromArgb(172,172,172)
    Accent=[Drawing.Color]::FromArgb(40,140,80); AccentDark=[Drawing.Color]::FromArgb(32,118,66); Surface=[Drawing.Color]::White
    Page=[Drawing.SystemColors]::Control; Hover=[Drawing.Color]::FromArgb(230,238,248)
    Ok=[Drawing.Color]::DarkGreen; Warn=[Drawing.Color]::FromArgb(176,96,0); Error=[Drawing.Color]::Firebrick
}
# Native look like the earlier version: system buttons, only the main action is green.
function Set-FlatButton($Button,[switch]$Primary) {
    $ui=$script:Ui
    if($Primary){$Button.FlatStyle='Flat';$Button.UseVisualStyleBackColor=$false;$Button.BackColor=$ui.Accent;$Button.ForeColor=[Drawing.Color]::White;$Button.FlatAppearance.BorderSize=0;$Button.FlatAppearance.MouseOverBackColor=$ui.AccentDark}
    else{$Button.FlatStyle='Standard';$Button.UseVisualStyleBackColor=$true}
}
function Get-ProductQueueUrls($Editor) {
    @($Editor.Rows|ForEach-Object{$_.Url.Text.Trim()}|Where-Object{$_}|Select-Object -Unique)
}

function Update-ProductQueueRow($Editor,$Row) {
    $url=$Row.Url.Text.Trim()
    if($url -eq $Row.BoundUrl){return}
    $Row.BoundUrl=$url;$Row.ImagePath='';Set-FeedbackPreview $Row.Preview ''
    $entry=@((Read-ManualReferenceMap $Editor.MapPath).entries|Where-Object product_url -eq $url)
    $Row.Status.ForeColor=$script:Ui.Muted
    $products=@(if($entry.Count){Get-ManualProducts $entry[0]})
    $scenes=@($products|ForEach-Object{@($_.scenes)})
    $first=@($products|Where-Object file)+@($scenes)|Select-Object -First 1
    if($first){
        try{
            Set-FeedbackPreview $Row.Preview $first.file;$Row.ImagePath=$first.file
            if(@($scenes|Where-Object{-not (Test-Path -LiteralPath $_.file)}).Count){throw 'missing'}
            if(@($products|Where-Object{-not @($_.scenes).Count}).Count){$Row.Status.Text='● Có ảnh gốc chưa có review';$Row.Status.ForeColor=$script:Ui.Warn}
            else{$Row.Status.Text=if($products.Count -gt 1){"● $($products.Count) mẫu · $($scenes.Count) ảnh"}elseif($scenes.Count -gt 1){"● $($scenes.Count) ảnh"}else{'● Đã có ảnh'};$Row.Status.ForeColor=$script:Ui.Ok}
        }catch{$Row.Status.Text='Không đọc được ảnh, hãy gắn lại.';$Row.Status.ForeColor=$script:Ui.Error}
    }else{$Row.Status.Text=if($url){'● Chưa có ảnh'}else{'Chưa có link'};if($url){$Row.Status.ForeColor=$script:Ui.Warn}}
    if($Editor.OnChanged){& $Editor.OnChanged}
}

# Small copy for thumbnails so the strip never holds full-size bitmaps.
function New-ThumbnailImage([string]$Path,[int]$Size=72) {
    $stream=[IO.File]::OpenRead($Path)
    try{
        $loaded=[Drawing.Image]::FromStream($stream,$false,$false)
        try{$scale=[Math]::Min($Size/$loaded.Width,$Size/$loaded.Height);return [Drawing.Bitmap]::new($loaded,[Math]::Max(1,[int]($loaded.Width*$scale)),[Math]::Max(1,[int]($loaded.Height*$scale)))}finally{$loaded.Dispose()}
    }finally{$stream.Dispose()}
}

# A small × that appears while the pointer is over an image; clicking it removes that image.
function Add-RemoveOverlay($Picture,[scriptblock]$OnRemove) {
    $x=New-Object Windows.Forms.Label -Property @{Text='×';Size='22,22';TextAlign='MiddleCenter';Cursor='Hand';Visible=$false;BackColor=[Drawing.Color]::FromArgb(15,23,42);ForeColor=[Drawing.Color]::White;Font=(New-Object Drawing.Font('Segoe UI',10))}
    $x.Location=[Drawing.Point]::new($Picture.Width-24,2);$x.Anchor='Top,Right'
    $Picture.Controls.Add($x)
    $show={if($Picture.Image){$x.Visible=$true}}.GetNewClosure()
    $hide={if(-not $Picture.ClientRectangle.Contains($Picture.PointToClient([Windows.Forms.Cursor]::Position))){$x.Visible=$false}}.GetNewClosure()
    $Picture.Add_MouseEnter($show);$Picture.Add_MouseLeave($hide);$x.Add_MouseLeave($hide)
    $x.Add_Click($OnRemove)
}

# Adds one or more scene images to the link; each image produces its own result.
function Set-ProductQueueReference($Editor,$Row,[string[]]$Source) {
    foreach($path in @($Source|Where-Object{$_})){[void](Save-ManualReference $Editor.Root $Row.Url.Text.Trim() $path)}
    $Row.BoundUrl=$null;Update-ProductQueueRow $Editor $Row
}

function Add-ProductQueueLinks($Editor,[string]$Text) {
    $urls=@($Text -split '\r?\n'|ForEach-Object{$_.Trim()}|Where-Object{$_ -and -not $_.StartsWith('#')}|Select-Object -Unique)
    foreach($url in $urls){$uri=$null;if(-not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https')){throw "Link không hợp lệ: $url"}}
    foreach($url in $urls){
        if($url -in @(Get-ProductQueueUrls $Editor)){continue}
        $empty=@($Editor.Rows|Where-Object{-not $_.Url.Text.Trim()}|Select-Object -First 1)
        if($empty.Count){$empty[0].Url.Text=$url}else{[void](Add-ProductQueueRow $Editor $url)}
    }
}

function Remove-ProductQueueRow($Editor,$Row) {
    Set-FeedbackPreview $Row.Preview ''
    [void]$Editor.Rows.Remove($Row);$Editor.Flow.Controls.Remove($Row.Card);$Row.Card.Dispose()
    for($i=0;$i -lt $Editor.Rows.Count;$i++){$Editor.Rows[$i].Number.Text='#'+($i+1)}
    if($Editor.OnChanged){& $Editor.OnChanged}
}

function Add-ProductQueueRow($Editor,[string]$Url='') {
    $width=[Math]::Max(700,$Editor.Flow.ClientSize.Width-40)
    $ui=$script:Ui
    $card=New-Object Windows.Forms.Panel -Property @{Size=(New-Object Drawing.Size($width,60));BackColor=$ui.Surface;Margin='0,0,0,8';Cursor='Hand'}
    $card.Add_Paint({$pen=New-Object Drawing.Pen($script:Ui.Line);try{$_.Graphics.DrawRectangle($pen,0,0,$this.Width-1,$this.Height-1)}finally{$pen.Dispose()}})
    $number=New-Object Windows.Forms.Label -Property @{Text=('#'+($Editor.Rows.Count+1));Location='10,19';Size='40,22';ForeColor=$ui.Muted}
    $picture=New-Object Windows.Forms.PictureBox -Property @{Name='ReferencePreview';Location=(New-Object Drawing.Point(($width-192),8));Size='44,44';Anchor='Top,Right';SizeMode='Zoom';BackColor=$ui.Page;AllowDrop=$true}
    $box=New-Object Windows.Forms.TextBox -Property @{Name='ProductUrl';Location='52,20';Size=(New-Object Drawing.Size(($width-397),22));Anchor='Top,Left,Right';ReadOnly=$true;BorderStyle='None';BackColor=$ui.Surface;ForeColor=$ui.Ink;Cursor='Hand';TabStop=$false}
    $status=New-Object Windows.Forms.Label -Property @{Name='ReferenceStatus';Location=(New-Object Drawing.Point(($width-340),19));Size='140,24';Anchor='Top,Right';AutoEllipsis=$true;ForeColor=$ui.Muted}
    $open=New-Object Windows.Forms.Button -Property @{Name='PreviewProduct';Text='Xem / sửa';Location=(New-Object Drawing.Point(($width-136),12));Size='90,34';Anchor='Top,Right'}
    $remove=New-Object Windows.Forms.Button -Property @{Name='RemoveProduct';Text='×';Location=(New-Object Drawing.Point(($width-40),12));Size='32,34';Anchor='Top,Right';AccessibleName='Xóa sản phẩm'}
    Set-FlatButton $open;Set-FlatButton $remove
    $row=[pscustomobject]@{Card=$card;Url=$box;Preview=$picture;Status=$status;Number=$number;ImagePath='';BoundUrl=$null}
    [void]$Editor.Rows.Add($row);$card.Controls.AddRange(@($number,$box,$status,$picture,$open,$remove));$Editor.Flow.Controls.Add($card)
    $box.Add_TextChanged({Update-ProductQueueRow $Editor $row}.GetNewClosure())
    $show={Show-ProductQueueDialog $Editor $row}.GetNewClosure()
    foreach($control in @($card,$box,$number,$picture,$status,$open)){$control.Add_Click($show)}
    # Hover highlight on the whole row; the pointer moving between child controls must not flicker it off.
    $hoverOn={$card.BackColor=$script:Ui.Hover;$box.BackColor=$script:Ui.Hover;$card.Invalidate()}.GetNewClosure()
    $hoverOff={if(-not $card.ClientRectangle.Contains($card.PointToClient([Windows.Forms.Cursor]::Position))){$card.BackColor=$script:Ui.Surface;$box.BackColor=$script:Ui.Surface;$card.Invalidate()}}.GetNewClosure()
    foreach($control in @($card,$box,$number,$picture,$status)){$control.Add_MouseEnter($hoverOn);$control.Add_MouseLeave($hoverOff)}
    $picture.Add_DragEnter({if($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$_.Effect=[Windows.Forms.DragDropEffects]::Copy}})
    $picture.Add_DragDrop({try{$files=$_.Data.GetData([Windows.Forms.DataFormats]::FileDrop);if($files.Count){Set-ProductQueueReference $Editor $row @($files)}}catch{$row.Status.Text=$_.Exception.Message;$row.Status.ForeColor=[Drawing.Color]::Firebrick}}.GetNewClosure())
    $remove.Add_Click({Remove-ProductQueueRow $Editor $row}.GetNewClosure())
    $box.Text=$Url;Update-ProductQueueRow $Editor $row
    return $row
}

# Large view of one image; the popup itself keeps small thumbnails only.
function Show-ImagePreview($Owner,[string]$Path,[string]$Title) {
    $dialog=New-Object Windows.Forms.Form -Property @{Text=$Title;ClientSize='760,560';StartPosition='CenterParent';Font=(New-Object Drawing.Font('Segoe UI',10));ShowInTaskbar=$false;MinimizeBox=$false}
    $picture=New-Object Windows.Forms.PictureBox -Property @{Location='12,12';Size='736,490';SizeMode='Zoom';BackColor=[Drawing.Color]::WhiteSmoke;Anchor='Top,Bottom,Left,Right'}
    $close=New-Object Windows.Forms.Button -Property @{Text='Đóng';Location='648,514';Size='100,32';Anchor='Bottom,Right';DialogResult='Cancel'}
    Set-FlatButton $close
    $dialog.Controls.AddRange(@($picture,$close));$dialog.CancelButton=$close
    try{Set-FeedbackPreview $picture $Path;[void]$dialog.ShowDialog($Owner)}finally{Set-FeedbackPreview $picture '';$dialog.Dispose()}
}

# Image files from a drop or the clipboard (an image is saved to a temporary PNG first).
function Get-DroppedImages($Data) {
    if($Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){return @($Data.GetData([Windows.Forms.DataFormats]::FileDrop)|Where-Object{$_ -match '\.(png|jpe?g)$'})}
    return @()
}

# Popup rows: one per product image, its review images beside it, then a row to add a product image.
# Every product + review pair becomes one generated image. Thumbnails are small; a click shows them large.
function Update-ProductDraftRows($State) {
    $ui=$script:Ui;$flow=$State.Rows;$url=$State.Url.Text.Trim()
    foreach($old in @($flow.Controls)){foreach($pic in @($old.Controls|Where-Object{$_ -is [Windows.Forms.PictureBox]})){if($pic.Image){$pic.Image.Dispose()}};$old.Dispose()}
    $flow.Controls.Clear()
    $entry=@((Read-ManualReferenceMap $State.Editor.MapPath).entries|Where-Object product_url -eq $url)
    $products=@(if($entry.Count){Get-ManualProducts $entry[0]})
    $State.Products=$products
    if($State.Active -ge $products.Count){$State.Active=$products.Count-1}
    $width=[Math]::Max(600,$flow.ClientSize.Width-24)
    # Closures get their own copy of the state: GetNewClosure keeps only this block's variables.
    $newThumb={param($path,$title,$onRemove,$st)
        $pic=New-Object Windows.Forms.PictureBox -Property @{Size='56,56';SizeMode='Zoom';BorderStyle='FixedSingle';BackColor=[Drawing.Color]::WhiteSmoke;Margin='0,0,6,0';Cursor='Hand';Tag=$path}
        try{if($path -and (Test-Path -LiteralPath $path)){$pic.Image=New-ThumbnailImage $path 56}}catch{}
        $pic.Add_Click({if($pic.Image){Show-ImagePreview $st.Dialog $path $title}}.GetNewClosure())
        Add-RemoveOverlay $pic $onRemove
        $pic
    }
    $newAdd={param([scriptblock]$onPick)
        $add=New-Object Windows.Forms.Button -Property @{Text='+';Size='56,56';Margin='0,0,6,0';Font=(New-Object Drawing.Font('Segoe UI',14));ForeColor=$ui.Muted}
        Set-FlatButton $add;$add.Add_Click($onPick);$add
    }
    for($i=0;$i -lt $products.Count;$i++){
        $index=$i;$product=$products[$i]
        $row=New-Object Windows.Forms.FlowLayoutPanel -Property @{Size=(New-Object Drawing.Size($width,70));Padding='6,6,6,6';Margin='0,0,0,1';WrapContents=$false;AllowDrop=$true;BackColor=$(if($i -eq $State.Active){$ui.Hover}else{[Drawing.Color]::White})}
        if($product.file){$row.Controls.Add((& $newThumb $product.file "Ảnh gốc #$($i+1)" {Remove-ManualProduct $State.Editor.MapPath $State.Url.Text.Trim() $index;Update-ProductDraftRows $State}.GetNewClosure() $State))}
        else{$row.Controls.Add((New-Object Windows.Forms.Label -Property @{Text='Ảnh từ link';Size='56,56';TextAlign='MiddleCenter';ForeColor=$ui.Muted;Margin='0,0,6,0'}))}
        $row.Controls.Add((New-Object Windows.Forms.Label -Property @{Text='→';Size='18,56';TextAlign='MiddleCenter';ForeColor=$ui.Muted;Margin='0,0,6,0'}))
        $scenes=@($product.scenes)
        for($k=0;$k -lt $scenes.Count;$k++){
            $scene=$k
            $row.Controls.Add((& $newThumb $scenes[$k].file "Ảnh review $($k+1) · ảnh gốc #$($i+1)" {Remove-ManualScene $State.Editor.MapPath $State.Url.Text.Trim() $scene $index;Update-ProductDraftRows $State}.GetNewClosure() $State))
        }
        # Review images for this product image: from this computer or from the Drive library.
        $fromComputer=& $newAdd {$State.Active=$index;Add-ProductDraftImages $State (Select-ImageFiles $true) $index}.GetNewClosure()
        $fromDrive=& $newAdd {$State.Active=$index;Add-ProductDraftImages $State (Show-DriveSourcePicker $State.Dialog $State.Editor) $index}.GetNewClosure()
        foreach($b in @($fromComputer,$fromDrive)){$b.Font=New-Object Drawing.Font('Segoe UI',8)}
        $fromComputer.Text='+ Máy';$fromDrive.Text='+ Drive'
        $row.Controls.AddRange(@($fromComputer,$fromDrive))
        # The row under the pointer (or clicked) receives pasted images.
        $select={$State.Active=$index;foreach($r in @($State.Rows.Controls)){$r.BackColor=[Drawing.Color]::White};$row.BackColor=$script:Ui.Hover}.GetNewClosure()
        $row.Add_Click($select);$row.Add_MouseEnter($select)
        foreach($child in @($row.Controls)){$child.Add_MouseEnter($select)}
        $row.Add_DragEnter({if($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$_.Effect='Copy'}})
        $row.Add_DragDrop({$State.Active=$index;Add-ProductDraftImages $State (Get-DroppedImages $_.Data) $index}.GetNewClosure())
        $flow.Controls.Add($row)
    }
    $addRow=New-Object Windows.Forms.FlowLayoutPanel -Property @{Size=(New-Object Drawing.Size($width,70));Padding='6,6,6,6';WrapContents=$false;AllowDrop=$true;BackColor=[Drawing.Color]::White}
    $addRow.Controls.Add((& $newAdd {Add-ProductDraftImages $State (Select-ImageFiles $true) -1}.GetNewClosure()))
    $addRow.Controls.Add((New-Object Windows.Forms.Label -Property @{Text='Thêm ảnh gốc';Size='160,56';TextAlign='MiddleLeft';ForeColor=$ui.Muted}))
    $toProduct={$State.Active=-1;foreach($r in @($State.Rows.Controls)){$r.BackColor=[Drawing.Color]::White}}.GetNewClosure()
    $addRow.Add_MouseEnter($toProduct);foreach($child in @($addRow.Controls)){$child.Add_MouseEnter($toProduct)}
    $addRow.Add_DragEnter({if($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$_.Effect='Copy'}})
    $addRow.Add_DragDrop({Add-ProductDraftImages $State (Get-DroppedImages $_.Data) -1}.GetNewClosure())
    $flow.Controls.Add($addRow)
    $reviews=@($products|ForEach-Object{@($_.scenes)}).Count;$missing=@($products|Where-Object{-not @($_.scenes).Count}).Count
    $status=$State.Status
    if(-not $url){$status.Text='Chưa có link';$status.ForeColor=$ui.Muted}
    elseif(-not $products.Count){$status.Text='● Chưa có ảnh';$status.ForeColor=$ui.Warn}
    elseif($missing){$status.Text="● $missing ảnh gốc chưa có ảnh review";$status.ForeColor=$ui.Warn}
    else{$status.Text="● $($products.Count) ảnh gốc · $reviews ảnh review → $reviews ảnh kết quả";$status.ForeColor=$ui.Ok}
}

function Select-ImageFiles([bool]$Multiple) {
    $picker=New-Object Windows.Forms.OpenFileDialog -Property @{Filter='Ảnh PNG/JPEG|*.png;*.jpg;*.jpeg';Multiselect=$Multiple}
    try{if($picker.ShowDialog() -eq 'OK'){return @($picker.FileNames)};return @()}finally{$picker.Dispose()}
}

# ProductIndex -1 adds product images; otherwise review images for that product image.
function Add-ProductDraftImages($State,[string[]]$Paths,[int]$ProductIndex) {
    $Paths=@($Paths|Where-Object{$_})
    if(-not $Paths.Count){return}
    try{
        $url=$State.Url.Text.Trim()
        if($ProductIndex -lt 0 -and -not $url){$url='https://local.invalid/products/manual-'+[Guid]::NewGuid().ToString('N');$State.Url.Text=$url}
        $uri=$null;if(-not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https')){throw 'Dán link hợp lệ trước khi thêm ảnh.'}
        foreach($path in $Paths){[void](Save-ManualReference $State.Editor.Root $url $path $(if($ProductIndex -lt 0){'Product'}else{'Scene'}) $ProductIndex)}
        if($ProductIndex -lt 0){$State.Active=[int]::MaxValue}
        Update-ProductDraftRows $State
    }catch{$State.Status.Text=$_.Exception.Message;$State.Status.ForeColor=$script:Ui.Error}
}

# Ctrl+V outside the link box: an image goes to the active row (or becomes a product image).
function Paste-ProductDraftImage($State) {
    $target=if(@($State.Products).Count -and $State.Active -ge 0){[Math]::Min($State.Active,@($State.Products).Count-1)}else{-1}
    if([Windows.Forms.Clipboard]::ContainsImage()){
        $image=[Windows.Forms.Clipboard]::GetImage();$path=Join-Path ([IO.Path]::GetTempPath()) ('clipboard-'+[Guid]::NewGuid().ToString('N')+'.png')
        try{$image.Save($path,[Drawing.Imaging.ImageFormat]::Png);Add-ProductDraftImages $State @($path) $target}finally{$image.Dispose();Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue}
    }elseif([Windows.Forms.Clipboard]::ContainsFileDropList()){Add-ProductDraftImages $State @([Windows.Forms.Clipboard]::GetFileDropList()) $target}
}

function Save-ProductQueueDraft($Editor,$State,$Target=$null) {
    $url=$State.Url.Text.Trim();$uri=$null
    if(-not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https')){throw 'Link sản phẩm không hợp lệ.'}
    foreach($item in $Editor.Rows){if($item -ne $Target -and $item.Url.Text.Trim() -eq $url){throw 'Link này đã có trong danh sách.'}}
    $entry=@((Read-ManualReferenceMap $State.Editor.MapPath).entries|Where-Object product_url -eq $url)
    $map=Read-ManualReferenceMap $Editor.MapPath;$map.entries=@($map.entries|Where-Object product_url -ne $url)
    New-Item -ItemType Directory -Path (Split-Path $Editor.MapPath -Parent) -Force|Out-Null
    Write-FeedbackJson $Editor.MapPath $map
    if($entry.Count){Copy-ManualEntry $Editor.Root $url $entry[0]}
    if(-not $Target){$Target=Add-ProductQueueRow $Editor $url}else{$Target.Url.Text=$url}
    $Editor.SourceGroup=$State.Editor.SourceGroup
    $map=Read-ManualReferenceMap $Editor.MapPath;$map.preferred_source_group=[string]$Editor.SourceGroup;Write-FeedbackJson $Editor.MapPath $map
    $Target.BoundUrl=$null;Update-ProductQueueRow $Editor $Target
    $Editor.Flow.ScrollControlIntoView($Target.Card)
}

function New-ProductQueueDialog($Editor,$Target=$null) {
    # Edits use an isolated map and snapshots until the user saves.
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('product-reference-'+[Guid]::NewGuid().ToString('N'))
    $mapPath=Join-Path $temp 'workspace/reference-inputs/references.json'
    New-Item -ItemType Directory -Path (Split-Path $mapPath -Parent) -Force|Out-Null
    Write-FeedbackJson $mapPath (Read-ManualReferenceMap $Editor.MapPath)
    $draftEditor=[pscustomobject]@{Root=$temp;MapPath=$mapPath;OnChanged=$null;ProjectRoot=$Editor.Root;SourceGroup=$Editor.SourceGroup}
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Ảnh sản phẩm gốc & ảnh review';ClientSize='760,430';FormBorderStyle='FixedDialog';MinimizeBox=$false;MaximizeBox=$false;StartPosition='CenterParent';Font=(New-Object Drawing.Font('Segoe UI',10));ShowInTaskbar=$false;BackColor=[Drawing.Color]::White;KeyPreview=$true}
    $urlBox=New-Object Windows.Forms.TextBox -Property @{Name='ProductUrl';Location='20,40';Size='720,28'}
    $rows=New-Object Windows.Forms.FlowLayoutPanel -Property @{Name='ProductImageRows';Location='20,100';Size='720,250';FlowDirection='TopDown';WrapContents=$false;AutoScroll=$true;BorderStyle='FixedSingle';BackColor=[Drawing.Color]::White;AllowDrop=$true}
    $status=New-Object Windows.Forms.Label -Property @{Name='ReferenceStatus';Location='20,358';Size='500,26';AutoEllipsis=$true}
    $save=New-Object Windows.Forms.Button -Property @{Name='SaveProduct';Text='Lưu sản phẩm';Location='516,388';Size='120,30'}
    $cancel=New-Object Windows.Forms.Button -Property @{Text='Hủy';Location='646,388';Size='94,30';DialogResult='Cancel'}
    foreach($b in @($save,$cancel)){Set-FlatButton $b}
    $dialog.Controls.AddRange(@(
        (New-Object Windows.Forms.Label -Property @{Text='Link sản phẩm';Location='20,16';AutoSize=$true}),$urlBox,
        (New-Object Windows.Forms.Label -Property @{Text='Ảnh gốc';Location='26,76';Size='80,22';ForeColor=$script:Ui.Muted}),
        (New-Object Windows.Forms.Label -Property @{Text='Ảnh review của ảnh gốc đó';Location='110,76';Size='300,22';ForeColor=$script:Ui.Muted}),
        $rows,$status,$save,$cancel))
    $dialog.CancelButton=$cancel
    $state=[pscustomobject]@{Editor=$draftEditor;Url=$urlBox;Rows=$rows;Status=$status;Dialog=$dialog;Products=@();Active=-1;TempFolder=$temp}
    $dialog.Tag=$state
    $urlBox.Add_TextChanged({$state.Active=-1;Update-ProductDraftRows $state}.GetNewClosure())
    $dialog.Add_KeyDown({if($_.Control -and $_.KeyCode -eq [Windows.Forms.Keys]::V -and -not $urlBox.Focused){$_.SuppressKeyPress=$true;Paste-ProductDraftImage $state}}.GetNewClosure())
    $rows.Add_DragEnter({if($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$_.Effect='Copy'}})
    $rows.Add_DragDrop({Add-ProductDraftImages $state (Get-DroppedImages $_.Data) -1}.GetNewClosure())
    $save.Add_Click({try{Save-ProductQueueDraft $Editor $state $Target;$dialog.DialogResult='OK';$dialog.Close()}catch{$status.Text=$_.Exception.Message;$status.ForeColor=[Drawing.Color]::Firebrick}}.GetNewClosure())
    $dialog.Add_Disposed({foreach($r in @($rows.Controls)){foreach($pic in @($r.Controls|Where-Object{$_ -is [Windows.Forms.PictureBox]})){if($pic.Image){$pic.Image.Dispose()}}};Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}.GetNewClosure())
    $urlBox.Text=if($Target){$Target.Url.Text}else{''}
    Update-ProductDraftRows $state
    return $dialog
}

# "Từ kho Drive": the group's images already on this machine; Đồng bộ brings it up to date with Drive
# (new or changed files only, deleted ones removed), so picking never downloads or duplicates.
function Show-DriveSourcePicker($Owner,$Editor) {
    $ui=$script:Ui
    $libraryRoot=Join-Path $Editor.ProjectRoot 'data/source-photos'
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Chọn ảnh review từ kho Drive';ClientSize='760,540';FormBorderStyle='FixedDialog';MinimizeBox=$false;MaximizeBox=$false;StartPosition='CenterParent';Font=(New-Object Drawing.Font('Segoe UI',10));ShowInTaskbar=$false}
    $groups=New-Object Windows.Forms.ComboBox -Property @{Name='DriveGroup';Location='20,16';Size='220,28';DropDownStyle='DropDownList'}
    $sync=New-Object Windows.Forms.Button -Property @{Text='Đồng bộ';Location='250,14';Size='100,30'}
    $count=New-Object Windows.Forms.Label -Property @{Location='362,20';Size='380,24';ForeColor=$ui.Muted;AutoEllipsis=$true}
    $grid=New-Object Windows.Forms.FlowLayoutPanel -Property @{Location='20,52';Size='720,420';AutoScroll=$true;BorderStyle='FixedSingle';BackColor=[Drawing.Color]::White;Padding='6,6,6,6'}
    $bar=New-Object Windows.Forms.ProgressBar -Property @{Location='20,480';Size='400,8';Style='Marquee';MarqueeAnimationSpeed=30;Visible=$false}
    $add=New-Object Windows.Forms.Button -Property @{Text='Thêm';Location='536,490';Size='110,32';Enabled=$false}
    $cancel=New-Object Windows.Forms.Button -Property @{Text='Hủy';Location='656,490';Size='84,32';DialogResult='Cancel'}
    Set-FlatButton $add -Primary;Set-FlatButton $sync;Set-FlatButton $cancel
    $dialog.Controls.AddRange(@($groups,$sync,$count,$grid,$bar,$add,$cancel));$dialog.CancelButton=$cancel
    $state=@{Files=@();Shown=0;Picked=[ordered]@{};Paths=@();Proc=$null}
    $refreshCount={$count.Text=if(@($state.Files).Count){"Đã chọn $($state.Picked.Count) / $(@($state.Files).Count) ảnh"}else{'Nhóm chưa có trên máy. Bấm Đồng bộ để tải đủ ảnh.'};$add.Enabled=$state.Picked.Count -gt 0}.GetNewClosure()
    $showMore={
        foreach($old in @($grid.Controls|Where-Object Name -eq 'More')){$grid.Controls.Remove($old);$old.Dispose()}
        $end=[Math]::Min(@($state.Files).Count,$state.Shown+120)
        for($i=$state.Shown;$i -lt $end;$i++){
            $path=$state.Files[$i]
            $tile=New-Object Windows.Forms.PictureBox -Property @{Size='100,100';SizeMode='Zoom';Margin='3,3,3,3';Padding='3,3,3,3';BackColor=[Drawing.Color]::WhiteSmoke;Cursor='Hand';Tag=$path}
            try{$tile.Image=New-ThumbnailImage $path 94}catch{}
            $tile.Add_Click({
                $p=$this.Tag
                if($state.Picked.Contains($p)){$state.Picked.Remove($p);$this.BackColor=[Drawing.Color]::WhiteSmoke}
                else{$state.Picked[$p]=$true;$this.BackColor=$script:Ui.Accent}
                & $refreshCount
            }.GetNewClosure())
            $grid.Controls.Add($tile)
        }
        $state.Shown=$end
        if($end -lt @($state.Files).Count){$more=New-Object Windows.Forms.Button -Property @{Name='More';Text='Xem thêm';Size='100,100';Margin='3,3,3,3'};Set-FlatButton $more;$more.Add_Click({& $showMore}.GetNewClosure());$grid.Controls.Add($more)}
    }
    $load={
        foreach($old in @($grid.Controls)){if($old -is [Windows.Forms.PictureBox] -and $old.Image){$old.Image.Dispose()};$old.Dispose()}
        $grid.Controls.Clear();$state.Picked.Clear();$state.Shown=0
        $state.Files=@(Get-LocalSourceFiles $libraryRoot ([string]$groups.SelectedItem))
        & $showMore;& $refreshCount
    }.GetNewClosure()
    $showMore=$showMore.GetNewClosure()
    # Sync runs in its own process so the bar keeps moving.
    $out=Join-Path ([IO.Path]::GetTempPath()) "prb-sync-$PID.out";$err=Join-Path ([IO.Path]::GetTempPath()) "prb-sync-$PID.err"
    $timer=New-Object Windows.Forms.Timer -Property @{Interval=400}
    $timer.Add_Tick({
        if(-not $state.Proc.HasExited){return}
        $timer.Stop();$state.Proc.WaitForExit();$code=$state.Proc.ExitCode;$state.Proc.Dispose();$state.Proc=$null
        $bar.Visible=$false;$sync.Enabled=$true;$groups.Enabled=$true
        & $load
        $text=try{(Get-Content -LiteralPath $out -Raw -ErrorAction Stop).Trim()}catch{''}
        if($code -eq 0 -and $text -match '^(\d+)\|(\d+)\|(\d+)$'){$count.Text="Đã đồng bộ: $($Matches[1]) ảnh (tải mới $($Matches[2]), xoá $($Matches[3]))."}
        else{$count.Text='Chưa đồng bộ được. Kiểm tra mạng và mật khẩu app rồi thử lại.'}
    }.GetNewClosure())
    $sync.Add_Click({
        if(-not (Get-DriveConfig (Join-Path $Editor.ProjectRoot 'workspace'))){$count.Text='Đăng nhập mật khẩu app trước (Kiểm tra cấu hình).';return}
        $sync.Enabled=$false;$groups.Enabled=$false;$bar.Visible=$true;$count.Text="Đang đồng bộ nhóm $($groups.SelectedItem)…"
        $state.Proc=Start-Process powershell.exe -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $Editor.ProjectRoot 'src\sync-source.ps1')+'"'),'-Group',('"'+[string]$groups.SelectedItem+'"'))
        [void]$state.Proc.Handle
        $timer.Start()
    }.GetNewClosure())
    $groups.Add_SelectedIndexChanged($load)
    $add.Add_Click({$state.Paths=@($state.Picked.Keys);$Editor.SourceGroup=[string]$groups.SelectedItem;$dialog.DialogResult='OK';$dialog.Close()}.GetNewClosure())
    $dialog.Add_FormClosing({if($state.Proc){$_.Cancel=$true}}.GetNewClosure())
    $dialog.Add_Shown({
        foreach($g in @(Get-SourceGroupChoices $Editor.ProjectRoot $libraryRoot)){[void]$groups.Items.Add($g)}
        if($groups.Items.Contains($Editor.SourceGroup)){$groups.SelectedItem=$Editor.SourceGroup}elseif($groups.Items.Count){$groups.SelectedIndex=0}
    }.GetNewClosure())
    try{[void]$dialog.ShowDialog($Owner);return @($state.Paths)}
    finally{$timer.Dispose();foreach($c in @($grid.Controls)){if($c -is [Windows.Forms.PictureBox] -and $c.Image){$c.Image.Dispose()}};$dialog.Dispose();Remove-Item -LiteralPath $out,$err -Force -ErrorAction SilentlyContinue}
}


function Show-ProductQueueDialog($Editor,$Target=$null) {
    $dialog=New-ProductQueueDialog $Editor $Target
    try{[void]$dialog.ShowDialog($Editor.Panel.FindForm())}finally{$dialog.Dispose()}
}

function Show-ProductQueueBulkDialog($Editor) {
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Thêm nhiều link';ClientSize='700,420';MinimumSize='600,380';StartPosition='CenterParent';Font=(New-Object Drawing.Font('Segoe UI',10));ShowInTaskbar=$false}
    $hint=New-Object Windows.Forms.Label -Property @{Text='Mỗi dòng một link. Thêm xong, bấm từng dòng trong danh sách để gắn ảnh.';Location='16,16';Size='668,44';Anchor='Top,Left,Right'}
    $text=New-Object Windows.Forms.TextBox -Property @{Name='BulkUrls';Multiline=$true;ScrollBars='Vertical';Location='16,66';Size='668,258';Anchor='Top,Bottom,Left,Right'}
    $status=New-Object Windows.Forms.Label -Property @{Location='16,334';Size='668,30';Anchor='Bottom,Left,Right';ForeColor=[Drawing.Color]::Firebrick}
    $save=New-Object Windows.Forms.Button -Property @{Text='Thêm vào danh sách';Location='376,372';Size='186,32';Anchor='Bottom,Right'}
    $cancel=New-Object Windows.Forms.Button -Property @{Text='Hủy';Location='574,372';Size='110,32';Anchor='Bottom,Right';DialogResult='Cancel'}
    $dialog.Controls.AddRange(@($hint,$text,$status,$save,$cancel));$dialog.CancelButton=$cancel
    $save.Add_Click({try{if(-not $text.Text.Trim()){throw 'Nhập ít nhất một link.'};Add-ProductQueueLinks $Editor $text.Text;$dialog.Close()}catch{$status.Text=$_.Exception.Message}}.GetNewClosure())
    try{[void]$dialog.ShowDialog($Editor.Panel.FindForm())}finally{$dialog.Dispose()}
}

function Set-ProductQueueUrls($Editor,[string[]]$Urls) {
    foreach($row in @($Editor.Rows)){Set-FeedbackPreview $row.Preview '';$row.Card.Dispose()}
    $Editor.Flow.Controls.Clear();$Editor.Rows.Clear()
    foreach($url in @($Urls|Where-Object{$_ -and -not $_.Trim().StartsWith('#')}|Select-Object -Unique)){[void](Add-ProductQueueRow $Editor $url)}
}

function Save-ProductQueueEditor($Editor,[string]$QueuePath,[switch]$RequireReady) {
    $urls=@(Get-ProductQueueUrls $Editor)
    $duplicates=@($Editor.Rows|ForEach-Object{$_.Url.Text.Trim()}|Where-Object{$_}|Group-Object|Where-Object Count -gt 1)
    if($duplicates.Count){throw "Link bị trùng ở nhiều dòng: $($duplicates[0].Name). Mỗi link chỉ nên có một dòng."}
    foreach($url in $urls){$uri=$null;if(-not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https')){throw "Link không hợp lệ: $url"}}
    $map=Read-ManualReferenceMap $Editor.MapPath;$map.allow_library_fallback=$false
    if($RequireReady){
        foreach($url in $urls){$entry=@($map.entries|Where-Object product_url -eq $url)
            $scenes=@(if($entry.Count){Get-ManualScenes $entry[0]})
            if(-not $scenes.Count){throw "Chưa có ảnh review: $url"}
            if(@(Get-ManualProducts $entry[0]|Where-Object{-not @($_.scenes).Count}).Count){throw "Có ảnh gốc chưa gắn ảnh review: $url"}
            foreach($scene in $scenes){
                if(-not (Test-Path -LiteralPath $scene.file)){throw "Chưa có ảnh bối cảnh: $url"}
                if((Get-BytesHash ([IO.File]::ReadAllBytes($scene.file))) -ine $scene.sha256){throw "Ảnh đã thay đổi; hãy gắn lại cho link: $url"}
            }
        }
    }
    New-Item -ItemType Directory -Path (Split-Path $Editor.MapPath -Parent) -Force|Out-Null
    Write-FeedbackJson $Editor.MapPath $map
    [IO.File]::WriteAllLines($QueuePath,[string[]]$urls,[Text.UTF8Encoding]::new($true))
}

function New-ProductQueueEditor([string]$ProjectRoot) {
    $panel=New-Object Windows.Forms.Panel -Property @{Name='ProductQueueEditor';Size='1076,350'}
    $toolbar=New-Object Windows.Forms.Panel -Property @{Dock='Top';Height=44}
    $flow=New-Object Windows.Forms.FlowLayoutPanel -Property @{Name='ProductRows';Dock='Fill';FlowDirection='TopDown';WrapContents=$false;AutoScroll=$true;Padding='10,10,10,6'}
    $add=New-Object Windows.Forms.Button -Property @{Name='AddProduct';Text='+ Thêm sản phẩm';Location='0,0';Size='160,34'}
    $bulk=New-Object Windows.Forms.Button -Property @{Text='Thêm nhiều link';Location='172,0';Size='150,34'}
    Set-FlatButton $add -Primary;$add.FlatAppearance.BorderSize=0;Set-FlatButton $bulk
    # SourceGroup: the Drive group last opened in "Từ kho Drive", offered first next time.
    $editor=[pscustomobject]@{Panel=$panel;Flow=$flow;Rows=[Collections.Generic.List[object]]::new();Root=$ProjectRoot;MapPath=(Join-Path $ProjectRoot 'workspace/reference-inputs/references.json');OnChanged=$null;SourceGroup=(Read-ManualReferenceMap (Join-Path $ProjectRoot 'workspace/reference-inputs/references.json')).preferred_source_group}
    $toolbar.Controls.AddRange(@($add,$bulk));$panel.Controls.AddRange(@($flow,$toolbar))
    $flow.Add_ClientSizeChanged({foreach($row in $editor.Rows){$row.Card.Width=[Math]::Max(700,$flow.ClientSize.Width-40)}}.GetNewClosure())
    $add.Add_Click({Show-ProductQueueDialog $editor}.GetNewClosure())
    $bulk.Add_Click({Show-ProductQueueBulkDialog $editor}.GetNewClosure())
    $panel.Add_Disposed({foreach($row in $editor.Rows){Set-FeedbackPreview $row.Preview ''}}.GetNewClosure())
    return $editor
}
