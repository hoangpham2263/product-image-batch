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
    if($Row.ProductPreview){
        Set-FeedbackPreview $Row.ProductPreview ''
        if($entry.Count -and $entry[0].product_file){Set-FeedbackPreview $Row.ProductPreview $entry[0].product_file}
    }
    $scenes=if($entry.Count){@(Get-ManualScenes $entry[0])}else{@()}
    $index=0
    if($Row.PSObject.Properties['SceneIndex']){$Row.SceneIndex=[Math]::Max(0,[Math]::Min($Row.SceneIndex,$scenes.Count-1));$index=$Row.SceneIndex}
    if($Row.PSObject.Properties['Thumbs']){Update-SceneThumbs $Editor $Row $scenes $index}
    if($scenes.Count -and (Test-Path -LiteralPath $scenes[$index].file)){
        $count=if($scenes.Count -gt 1){"● $($scenes.Count) ảnh"}else{'● Đã có ảnh'}
        try{Set-FeedbackPreview $Row.Preview $scenes[$index].file;$Row.ImagePath=$scenes[$index].file;$Row.Status.Text=$count;$Row.Status.ForeColor=$script:Ui.Ok}catch{$Row.Status.Text='Không đọc được ảnh, hãy gắn lại.';$Row.Status.ForeColor=$script:Ui.Error}
    }else{$Row.Status.Text=if($url){'● Chưa có ảnh'}else{'Chưa có link'};if($url){$Row.Status.ForeColor=$script:Ui.Warn}}
    if($Editor.OnChanged){& $Editor.OnChanged}
}

# Adds one or more scene images to the link; each image produces its own result.
function Update-SceneThumbs($Editor,$Row,$Scenes,[int]$Selected) {
    foreach($old in @($Row.Thumbs.Controls)){Set-FeedbackPreview $old '';$old.Dispose()}
    $Row.Thumbs.Controls.Clear()
    for($i=0;$i -lt @($Scenes).Count;$i++){
        $thumb=New-Object Windows.Forms.PictureBox -Property @{Size='72,72';SizeMode='Zoom';Margin='0,0,6,0';Cursor='Hand';BackColor=$script:Ui.Page;Padding=if($i -eq $Selected){'3,3,3,3'}else{'1,1,1,1'}}
        $thumb.BackColor=if($i -eq $Selected){$script:Ui.Accent}else{$script:Ui.Line}
        try{Set-FeedbackPreview $thumb $Scenes[$i].file}catch{}
        $index=$i
        $thumb.Add_Click({$Row.SceneIndex=$index;$Row.BoundUrl=$null;Update-ProductQueueRow $Editor $Row}.GetNewClosure())
        $Row.Thumbs.Controls.Add($thumb)
    }
}

function Set-ProductQueueReference($Editor,$Row,[string[]]$Source) {
    foreach($path in @($Source|Where-Object{$_})){[void](Save-ManualReference $Editor.Root $Row.Url.Text.Trim() $path)}
    if($Row.PSObject.Properties['SceneIndex']){$Row.SceneIndex=[int]::MaxValue}
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

function Paste-ProductQueueRow($Editor,$Row) {
    try{
        if([Windows.Forms.Clipboard]::ContainsImage()){
            $uri=$null;if(-not [Uri]::TryCreate($Row.Url.Text.Trim(),[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https')){throw 'Dán link hợp lệ vào dòng này trước khi dán ảnh.'}
            $image=[Windows.Forms.Clipboard]::GetImage();$folder=Join-Path $Editor.Root 'workspace/reference-inputs'
            New-Item -ItemType Directory -Path $folder -Force|Out-Null;$temporary=Join-Path $folder ('clipboard-'+[Guid]::NewGuid().ToString('N')+'.png')
            try{$image.Save($temporary,[Drawing.Imaging.ImageFormat]::Png);Set-ProductQueueReference $Editor $Row $temporary}finally{$image.Dispose();if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
        }elseif([Windows.Forms.Clipboard]::ContainsFileDropList()){$files=[Windows.Forms.Clipboard]::GetFileDropList();if($files.Count){Set-ProductQueueReference $Editor $Row @($files)}}
        elseif([Windows.Forms.Clipboard]::ContainsText()){$value=[Windows.Forms.Clipboard]::GetText();if(($value.Trim() -split '\r?\n').Count -gt 1){throw 'Popup này chỉ nhận một link. Dùng Thêm nhiều link để nhập hàng loạt.'};$Row.Url.Text=$value.Trim()}
        else{throw 'Clipboard chưa có link hoặc ảnh.'}
    }catch{$Row.Status.Text=$_.Exception.Message;$Row.Status.ForeColor=[Drawing.Color]::Firebrick}
}

function New-ProductQueueEditControls($Editor,[string]$Url='') {
    $card=New-Object Windows.Forms.Panel -Property @{Size='760,570';BackColor=[Drawing.Color]::White;BorderStyle='None';AllowDrop=$true}
    $box=New-Object Windows.Forms.TextBox -Property @{Name='ProductUrl';Location='20,42';Size='720,28';Anchor='Top,Left,Right'}
    $status=New-Object Windows.Forms.Label -Property @{Name='ReferenceStatus';Location='20,482';Size='720,30';Anchor='Bottom,Left,Right';AutoEllipsis=$true}
    $picture=New-Object Windows.Forms.PictureBox -Property @{Name='ReferencePreview';Location='20,112';Size='720,310';SizeMode='Zoom';BackColor=[Drawing.Color]::FromArgb(241,244,240);Anchor='Top,Bottom,Left,Right';AllowDrop=$true;TabStop=$true;BorderStyle='FixedSingle'}
    $paste=New-Object Windows.Forms.Button -Property @{Name='PasteRowImage';Text='Dán ảnh · Ctrl+V';Location='20,436';Size='164,32';Anchor='Bottom,Left'}
    $choose=New-Object Windows.Forms.Button -Property @{Text='Chọn ảnh…';Location='196,436';Size='120,32';Anchor='Bottom,Left'}
    $clear=New-Object Windows.Forms.Button -Property @{Name='ClearReference';Text='Bỏ ảnh này';Location='328,436';Size='110,32';Anchor='Bottom,Left'}
    # Every attached scene image is shown as a thumbnail; clicking one previews it above.
    $picture.Height=230
    $thumbs=New-Object Windows.Forms.FlowLayoutPanel -Property @{Name='SceneThumbs';Location='20,348';Size='720,80';Anchor='Bottom,Left,Right';AutoScroll=$true;WrapContents=$false;AllowDrop=$true;BackColor=[Drawing.Color]::White}
    $row=[pscustomobject]@{Card=$card;Url=$box;Preview=$picture;Status=$status;ImagePath='';BoundUrl=$null;SceneIndex=0;Thumbs=$thumbs}
    $card.Controls.AddRange(@($box,$status,$picture,$thumbs,$paste,$choose,$clear))
    $box.Add_TextChanged({Update-ProductQueueRow $Editor $row}.GetNewClosure())
    $key={if($_.Control -and $_.KeyCode -eq [Windows.Forms.Keys]::V){$_.SuppressKeyPress=$true;Paste-ProductQueueRow $Editor $row}}.GetNewClosure()
    $box.Add_KeyDown($key);$picture.Add_KeyDown($key);$paste.Add_Click({Paste-ProductQueueRow $Editor $row}.GetNewClosure())
    $picture.Add_Click({[void]$row.Url.Focus()}.GetNewClosure())
    $picture.Add_Paint({if(-not $picture.Image){[Windows.Forms.TextRenderer]::DrawText($_.Graphics,'Dán / kéo ảnh',$picture.Font,$picture.ClientRectangle,[Drawing.Color]::DimGray,([Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter))}}.GetNewClosure())
    $choose.Add_Click({$picker=New-Object Windows.Forms.OpenFileDialog -Property @{Filter='Ảnh PNG/JPEG|*.png;*.jpg;*.jpeg';Multiselect=$true};try{$picker.InitialDirectory=Get-SourcePhotoDirectory $Editor.LibraryRoot $Editor.SourceGroup;if($picker.ShowDialog() -eq 'OK'){Set-ProductQueueReference $Editor $row $picker.FileNames}}catch{$row.Status.Text=$_.Exception.Message;$row.Status.ForeColor=[Drawing.Color]::Firebrick}finally{$picker.Dispose()}}.GetNewClosure())
    $enter={if($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$_.Effect=[Windows.Forms.DragDropEffects]::Copy}}
    $drop={try{$files=$_.Data.GetData([Windows.Forms.DataFormats]::FileDrop);if($files.Count){Set-ProductQueueReference $Editor $row @($files)}}catch{$row.Status.Text=$_.Exception.Message;$row.Status.ForeColor=[Drawing.Color]::Firebrick}}.GetNewClosure()
    $card.Add_DragEnter($enter);$card.Add_DragDrop($drop);$picture.Add_DragEnter($enter);$picture.Add_DragDrop($drop);$thumbs.Add_DragEnter($enter);$thumbs.Add_DragDrop($drop)
    $clear.Add_Click({
        Remove-ManualScene $Editor.MapPath $row.Url.Text.Trim() $row.SceneIndex
        $row.BoundUrl=$null;Update-ProductQueueRow $Editor $row
    }.GetNewClosure())
    $box.Text=$Url;Update-ProductQueueRow $Editor $row
    return $row
}

function Add-ProductImageControls($Editor,$Row) {
    $Row.Card.Size=[Drawing.Size]::new(1040,570)
    $Row.Url.Width=1000;$Row.Status.Width=1000
    $Row.Preview.Size=[Drawing.Size]::new(680,230);$Row.Thumbs.Width=680
    $label=New-Object Windows.Forms.Label -Property @{Text='Ảnh sản phẩm gốc (không cần mở web)';Location='720,82';Size='300,26'}
    $preview=New-Object Windows.Forms.PictureBox -Property @{Name='ProductImagePreview';Location='720,112';Size='300,310';SizeMode='Zoom';BorderStyle='FixedSingle';AllowDrop=$true;TabStop=$true}
    $Row|Add-Member NoteProperty ProductPreview $preview
    $choose=New-Object Windows.Forms.Button -Property @{Text='Chọn ảnh sản phẩm';Location='720,436';Size='180,32'}
    $clear=New-Object Windows.Forms.Button -Property @{Text='Bỏ ảnh';Location='910,436';Size='110,32'}
    $attach={param($path)
        if(-not $Row.Url.Text.Trim()){$Row.Url.Text='https://local.invalid/products/manual-'+[Guid]::NewGuid().ToString('N')}
        [void](Save-ManualReference $Editor.Root $Row.Url.Text.Trim() $path Product)
        $Row.BoundUrl=$null;Update-ProductQueueRow $Editor $Row
    }.GetNewClosure()
    $choose.Add_Click({
        $picker=New-Object Windows.Forms.OpenFileDialog -Property @{Filter='Ảnh PNG/JPEG|*.png;*.jpg;*.jpeg'}
        try{if($picker.ShowDialog() -eq 'OK'){& $attach $picker.FileName}}catch{$Row.Status.Text=$_.Exception.Message}finally{$picker.Dispose()}
    }.GetNewClosure())
    $preview.Add_DragEnter({if($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$_.Effect='Copy'}})
    $preview.Add_DragDrop({try{& $attach ($_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)[0])}catch{$Row.Status.Text=$_.Exception.Message}}.GetNewClosure())
    $pasteProduct={
            try{
                if([Windows.Forms.Clipboard]::ContainsImage()){
                    $image=[Windows.Forms.Clipboard]::GetImage();$path=Join-Path $Editor.Root 'clipboard-product.png'
                    try{$image.Save($path,[Drawing.Imaging.ImageFormat]::Png);& $attach $path}finally{$image.Dispose();Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue}
                }elseif([Windows.Forms.Clipboard]::ContainsFileDropList()){& $attach ([Windows.Forms.Clipboard]::GetFileDropList()[0])}
            }catch{$Row.Status.Text=$_.Exception.Message}
    }.GetNewClosure()
    $preview.Add_KeyDown({if($_.Control -and $_.KeyCode -eq 'V'){$_.SuppressKeyPress=$true;& $pasteProduct}}.GetNewClosure())
    $paste=New-Object Windows.Forms.Button -Property @{Name='PasteProductImage';Text='Dán ảnh sản phẩm';Location='720,474';Size='180,32'}
    $paste.Add_Click($pasteProduct)
    $Row.Status.Width=680
    $clear.Add_Click({
        $map=Read-ManualReferenceMap $Editor.MapPath
        foreach($entry in @($map.entries|Where-Object product_url -eq $Row.Url.Text.Trim())){$entry.PSObject.Properties.Remove('product_file');$entry.PSObject.Properties.Remove('product_sha256')}
        $map.entries=@($map.entries|Where-Object{@(Get-ManualScenes $_).Count -or $_.product_file})
        Write-FeedbackJson $Editor.MapPath $map;$Row.BoundUrl=$null;Update-ProductQueueRow $Editor $Row
    }.GetNewClosure())
    $Row.Card.Controls.AddRange(@($label,$preview,$choose,$clear,$paste))
    $sceneLabel=New-Object Windows.Forms.Label -Property @{Text='Ảnh bối cảnh';Location='560,82';Size='140,26'}
    $Row.Card.Controls.Add($sceneLabel)
    $Row.BoundUrl=$null;Update-ProductQueueRow $Editor $Row
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

function Save-ProductQueueDraft($Editor,$State,$Target=$null) {
    $draft=$State.Row;$url=$draft.Url.Text.Trim();$uri=$null
    if(-not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https')){throw 'Link sản phẩm không hợp lệ.'}
    foreach($item in $Editor.Rows){if($item -ne $Target -and $item.Url.Text.Trim() -eq $url){throw 'Link này đã có trong danh sách.'}}
    $entry=@((Read-ManualReferenceMap $State.Editor.MapPath).entries|Where-Object product_url -eq $url)
    $map=Read-ManualReferenceMap $Editor.MapPath;$map.entries=@($map.entries|Where-Object product_url -ne $url)
    New-Item -ItemType Directory -Path (Split-Path $Editor.MapPath -Parent) -Force|Out-Null
    Write-FeedbackJson $Editor.MapPath $map
    if($entry.Count){
        foreach($scene in @(Get-ManualScenes $entry[0])){[void](Save-ManualReference $Editor.Root $url $scene.file)}
        if($entry[0].product_file){[void](Save-ManualReference $Editor.Root $url $entry[0].product_file Product)}
    }
    if(-not $Target){$Target=Add-ProductQueueRow $Editor $url}else{$Target.Url.Text=$url}
    $Editor.SourceGroup=$State.Editor.SourceGroup
    $map=Read-ManualReferenceMap $Editor.MapPath;$map.preferred_source_group=$Editor.SourceGroup;Write-FeedbackJson $Editor.MapPath $map
    $Target.BoundUrl=$null;Update-ProductQueueRow $Editor $Target
    $Editor.Flow.ScrollControlIntoView($Target.Card)
}

function New-ProductQueueDialog($Editor,$Target=$null) {
    # Edits use an isolated map and snapshots until the user saves.
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('product-reference-'+[Guid]::NewGuid().ToString('N'))
    $mapPath=Join-Path $temp 'workspace/reference-inputs/references.json'
    New-Item -ItemType Directory -Path (Split-Path $mapPath -Parent) -Force|Out-Null
    Write-FeedbackJson $mapPath (Read-ManualReferenceMap $Editor.MapPath)
    $draftEditor=[pscustomobject]@{Root=$temp;MapPath=$mapPath;OnChanged=$null;LibraryRoot=$Editor.LibraryRoot;SourceGroup=$Editor.SourceGroup}
    $url=if($Target){$Target.Url.Text}else{''}
    $row=New-ProductQueueEditControls $draftEditor $url
    Add-ProductImageControls $draftEditor $row
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Ảnh sản phẩm & ảnh bối cảnh';ClientSize='1040,570';MinimumSize='1040,570';StartPosition='CenterParent';Font=(New-Object Drawing.Font('Segoe UI',10));ShowInTaskbar=$false}
    $row.Card.Dock='Fill'
    $label=New-Object Windows.Forms.Label -Property @{Text='Link sản phẩm (có thể chưa public; gắn ảnh sản phẩm để dùng trực tiếp)';Location='20,16';AutoSize=$true}
    $hint=New-Object Windows.Forms.Label -Property @{Text='Kho ảnh local:';Location='20,82';Size='110,26'}
    $groups=New-Object Windows.Forms.ComboBox -Property @{Name='SourcePhotoGroup';Location='132,78';Size='216,28';DropDownStyle='DropDownList'}
    foreach($group in @(Get-SourcePhotoGroups $Editor.LibraryRoot)){[void]$groups.Items.Add($group)}
    $groups.SelectedItem=$Editor.SourceGroup;if($groups.SelectedIndex -lt 0){$groups.SelectedIndex=0}
    $draftEditor.SourceGroup=[string]$groups.SelectedItem
    $groups.Add_SelectedIndexChanged({$draftEditor.SourceGroup=[string]$groups.SelectedItem}.GetNewClosure())
    $openFolder=New-Object Windows.Forms.Button -Property @{Name='OpenSourcePhotoFolder';Text='Mở thư mục';Location='360,78';Size='140,28'}
    $openFolder.Add_Click({try{$folder=Get-SourcePhotoDirectory $draftEditor.LibraryRoot $draftEditor.SourceGroup;Start-Process explorer.exe -ArgumentList ('"'+$folder+'"')}catch{$row.Status.Text=$_.Exception.Message}}.GetNewClosure())
    $save=New-Object Windows.Forms.Button -Property @{Name='SaveProduct';Text='Lưu sản phẩm';Location='760,526';Size='144,32';Anchor='Bottom,Right'}
    $cancel=New-Object Windows.Forms.Button -Property @{Text='Hủy';Location='916,526';Size='104,32';Anchor='Bottom,Right';DialogResult='Cancel'}
    $row.Card.Controls.AddRange(@($label,$hint,$groups,$openFolder,$save,$cancel));$dialog.Controls.Add($row.Card);$dialog.CancelButton=$cancel
    $state=[pscustomobject]@{Row=$row;Editor=$draftEditor;TempFolder=$temp};$dialog.Tag=$state
    $save.Add_Click({try{Save-ProductQueueDraft $Editor $state $Target;$dialog.DialogResult='OK';$dialog.Close()}catch{$row.Status.Text=$_.Exception.Message;$row.Status.ForeColor=[Drawing.Color]::Firebrick}}.GetNewClosure())
    $dialog.Add_Disposed({foreach($thumb in @($row.Thumbs.Controls)){Set-FeedbackPreview $thumb ''};Set-FeedbackPreview $row.Preview '';Set-FeedbackPreview $row.ProductPreview '';Remove-Item -LiteralPath $temp -Recurse -Force}.GetNewClosure())
    return $dialog
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
    $map=Read-ManualReferenceMap $Editor.MapPath;$map.allow_library_fallback=$Editor.Fallback.Checked
    $map.preferred_source_group=$Editor.SourceGroup
    if($RequireReady -and -not $map.allow_library_fallback){
        foreach($url in $urls){$entry=@($map.entries|Where-Object product_url -eq $url)
            $scenes=if($entry.Count){@(Get-ManualScenes $entry[0])}else{@()}
            if(-not $scenes.Count){throw "Chưa có ảnh bối cảnh: $url"}
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
    $footer=New-Object Windows.Forms.Panel -Property @{Dock='Bottom';Height=34}
    $flow=New-Object Windows.Forms.FlowLayoutPanel -Property @{Name='ProductRows';Dock='Fill';FlowDirection='TopDown';WrapContents=$false;AutoScroll=$true;Padding='10,10,10,6'}
    $add=New-Object Windows.Forms.Button -Property @{Name='AddProduct';Text='+ Thêm sản phẩm';Location='0,0';Size='160,34'}
    $bulk=New-Object Windows.Forms.Button -Property @{Text='Thêm nhiều link';Location='172,0';Size='150,34'}
    Set-FlatButton $add -Primary;$add.FlatAppearance.BorderSize=0;Set-FlatButton $bulk
    $tip=New-Object Windows.Forms.Label -Property @{Text='Bấm dòng để xem / sửa.';Location='338,5';Size='300,24';ForeColor=$script:Ui.Muted;TextAlign='MiddleLeft'}
    $fallback=New-Object Windows.Forms.CheckBox -Property @{Name='AllowLibraryFallback';Text='Tự tìm trong kho data cho dòng chưa có ảnh';Location='0,5';Size='650,26';ForeColor=$script:Ui.Muted}
    $editor=[pscustomobject]@{Panel=$panel;Flow=$flow;Rows=[Collections.Generic.List[object]]::new();Root=$ProjectRoot;MapPath=(Join-Path $ProjectRoot 'workspace/reference-inputs/references.json');Fallback=$fallback;OnChanged=$null;LibraryRoot=(Join-Path $ProjectRoot 'data/source-photos');SourceGroup='Áo'}
    $editor.SourceGroup=(Read-ManualReferenceMap $editor.MapPath).preferred_source_group
    $fallback.Checked=[bool](Read-ManualReferenceMap $editor.MapPath).allow_library_fallback
    $toolbar.Controls.AddRange(@($add,$bulk,$tip));$footer.Controls.Add($fallback);$panel.Controls.AddRange(@($flow,$footer,$toolbar))
    $flow.Add_ClientSizeChanged({foreach($row in $editor.Rows){$row.Card.Width=[Math]::Max(700,$flow.ClientSize.Width-40)}}.GetNewClosure())
    $add.Add_Click({Show-ProductQueueDialog $editor}.GetNewClosure())
    $bulk.Add_Click({Show-ProductQueueBulkDialog $editor}.GetNewClosure())
    $panel.Add_Disposed({foreach($row in $editor.Rows){Set-FeedbackPreview $row.Preview ''}}.GetNewClosure())
    return $editor
}
