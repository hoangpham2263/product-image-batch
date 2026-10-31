# Content MXH on Windows: the macOS page (ui/index.html) in WinForms. Sản phẩm & ảnh with Thao tác (400px) beside it,
# the run row, then the chosen product's results: its images on the left, a post per chosen platform on the right.
# Posts follow the same rules (src/model.ps1); the AI step is not built on either platform yet.
param([switch]$BuildOnly)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $toolRoot '../../hub/native-window.ps1')
. (Join-Path $PSScriptRoot 'model.ps1')
$shell=New-NativeToolWindow 'Content MXH' $toolRoot;$form=$shell.Form
$statePath=Join-Path $toolRoot 'workspace/windows-state.json'
$tones=[ordered]@{story='Kể chuyện';short='Ngắn gọn';sale='Bán hàng'}
$platformIds=@($script:SocialPlatforms | ForEach-Object {$_.id})
$vi=[Globalization.CultureInfo]::GetCultureInfo('vi-VN')

# Saved like the page's localStorage, plus the original images (by path: Windows can open them again).
function ConvertTo-SocialRow($Row) {
    $sources=New-Object Collections.ArrayList
    foreach($source in @($Row.sources)){if($source -and $source.path){[void]$sources.Add(@{path=[string]$source.path;scenes=[Math]::Min(6,[Math]::Max(1,[int]$source.scenes))})}}
    $id=if($Row.id){[string]$Row.id}else{[Guid]::NewGuid().ToString('N')}
    return @{id=$id;name=[string]$Row.name;brand=[string]$Row.brand;link=[string]$Row.link;points=[string]$Row.points;tags=[string]$Row.tags;sources=$sources}
}
$state=@{rows=(New-Object Collections.ArrayList);tone='story';note='';platforms=@('facebook','instagram');tab='';current=''}
$saved=Read-NativeState $statePath $null
if($saved){
    if($tones.Contains([string]$saved.tone)){$state.tone=[string]$saved.tone}
    $state.note=[string]$saved.note;$state.tab=[string]$saved.tab;$state.current=[string]$saved.current
    $chosen=@($platformIds | Where-Object {@($saved.platforms) -contains $_});if($chosen.Count){$state.platforms=$chosen}
    foreach($row in @($saved.rows)){if($row){[void]$state.rows.Add((ConvertTo-SocialRow $row))}}
}
# Pictures are read once and kept small: thumbnails by size and path, and each platform's logo on and off.
$pictures=@{}
function Get-SocialPicture([string]$Path,[int]$Size) {
    $key="$Size|$Path"
    if(-not $pictures.ContainsKey($key)){$pictures[$key]=$(try{[ToolsHubNative.Look]::Thumb($Path,$Size)}catch{$null})}
    return $pictures[$key]
}
$logos=@{}
foreach($id in $platformIds){
    $on=Get-SocialPicture (Join-Path $toolRoot "assets/$id.png") 16
    $logos[$id]=@{On=$on;Off=$(if($on){[ToolsHubNative.Look]::Faded($on)}else{$null})}
}
function Get-SocialPlatform([string]$Id) {return @($script:SocialPlatforms | Where-Object {$_.id -eq $Id})[0]}

# ----- Layout: the top row (318px), 12px, the run row, 12px, the results -----
$top=New-Object Windows.Forms.Panel -Property @{Dock='Top';Height=318}
$runGroup=New-NativeGroup '' Top 62
$resultGroup=New-NativeGroup 'Kết quả' Fill
Add-NativeStack $shell.Body @($top,(New-NativeGap Top 12),$runGroup,(New-NativeGap Top 12),$resultGroup)

# Sản phẩm & ảnh: + Thêm sản phẩm, Xóa tất cả, then the products as rows in a 224px list.
$productsGroup=New-NativeGroup 'Sản phẩm & ảnh' Fill
$actionsGroup=New-NativeGroup 'Thao tác' Right 400
Add-NativeStack $top @($actionsGroup,(New-NativeGap Right 16),$productsGroup)
$toolsRow=New-Object Windows.Forms.Panel -Property @{Dock='Top';Height=32}
$add=New-NativeButton '+ Thêm sản phẩm' -Primary;$add.Width=160
$clear=New-NativeButton 'Xóa tất cả';$clear.Width=120;$clear.Left=172
$toolsRow.Controls.AddRange(@($add,$clear))
$rowsBox=New-Object ToolsHubNative.Box -Property @{Dock='Fill';Border=[Drawing.Color]::Black;Padding='10,10,10,6'}
$rowsPanel=New-Object Windows.Forms.Panel -Property @{Dock='Fill';AutoScroll=$true;BackColor=[Drawing.Color]::White}
$rowsBox.Controls.Add($rowsPanel)
Add-NativeStack $productsGroup @($toolsRow,(New-NativeGap Top 10),$rowsBox)

# Thao tác: Đăng lên (a button per platform with its logo), Giọng văn, Lời nhắn cho AI.
$platformGrid=New-Object Windows.Forms.TableLayoutPanel -Property @{Dock='Top';Height=36;ColumnCount=$platformIds.Count;RowCount=1;Margin='0,0,0,0'}
[void]$platformGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
$platformFont=New-Object Drawing.Font('Segoe UI',9.5)
for($i=0;$i -lt $platformIds.Count;$i++){
    [void]$platformGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',(100/$platformIds.Count))))
    $id=$platformIds[$i];$platform=Get-SocialPlatform $id
    $toggle=New-Object ToolsHubNative.Toggle -Property @{Text=$platform.name;Tag=$id;Dock='Fill';Font=$platformFont;Logo=$logos[$id].On;LogoOff=$logos[$id].Off;Margin=$(if($i -lt $platformIds.Count-1){'0,0,6,0'}else{'0,0,0,0'})}
    $platformGrid.Controls.Add($toggle,$i,0)
}
$toneSeg=New-NativeSeg @($tones.Keys | ForEach-Object {@{Id=$_;Text=$tones[$_]}}) -Fill
$note=New-Object Windows.Forms.TextBox -Property @{Dock='Fill';Multiline=$true;AcceptsReturn=$true;ScrollBars='Vertical';Text=$state.note}
Add-NativeStack $actionsGroup @((New-NativeLabel 'Đăng lên'),(New-NativeGap Top 4),$platformGrid,(New-NativeGap Top 12),(New-NativeLabel 'Giọng văn'),(New-NativeGap Top 4),$toneSeg,(New-NativeGap Top 12),(New-NativeLabel 'Lời nhắn cho AI'),(New-NativeGap Top 4),$note)

# Run row, as Product Review's: Bắt đầu, Dừng, the status.
$run=New-NativeButton 'Bắt đầu' -Primary;$run.Size='160,40';$run.Location='14,11'
$stop=New-NativeButton 'Dừng';$stop.Size='100,40';$stop.Location='186,11';$stop.Enabled=$false
$status=New-Object Windows.Forms.Label -Property @{Location='298,21';AutoSize=$true;ForeColor=$script:Ui.Muted;UseMnemonic=$false}
$runGroup.Controls.AddRange(@($run,$stop,$status))

# Kết quả: Ảnh tạo thành on the left (1 part), the post on the right (1.2 parts), 16px apart.
$resultGrid=New-Object Windows.Forms.TableLayoutPanel -Property @{Dock='Fill';ColumnCount=3;RowCount=1}
[void]$resultGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',45.45)))
[void]$resultGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',16)))
[void]$resultGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',54.55)))
[void]$resultGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
$resultGroup.Controls.Add($resultGrid)
$imageSide=New-Object Windows.Forms.Panel -Property @{Dock='Fill';Margin='0,0,0,0'}
$tiles=New-Object Windows.Forms.FlowLayoutPanel -Property @{Dock='Fill';AutoScroll=$true;FlowDirection='TopDown';WrapContents=$false}
$emptyTiles=New-Object ToolsHubNative.Box -Property @{Dock='Fill';Dashed=$true}
$imageLabel=New-Object Windows.Forms.Label -Property @{Text='Ảnh tạo thành';Dock='Top';Height=32;TextAlign='MiddleLeft'}
Add-NativeStack $imageSide @($imageLabel,(New-NativeGap Top 6),$tiles)
$imageSide.Controls.Add($emptyTiles);$emptyTiles.BringToFront()
$postSide=New-Object Windows.Forms.Panel -Property @{Dock='Fill';Margin='0,0,0,0'}
$postHead=New-Object Windows.Forms.Panel -Property @{Dock='Top';Height=32}
$copy=New-NativeButton 'Copy bài đăng';$copy.Width=130
$postHead.Controls.Add($copy)
$postHead.Add_Resize({param($sender) $copy.Left=[Math]::Max(0,$sender.ClientSize.Width-$copy.Width)})
$out=New-NativeOutput
$tipRow=New-Object Windows.Forms.Panel -Property @{Dock='Bottom';Height=18}
$smallFont=New-Object Drawing.Font('Segoe UI',9)
$tip=New-Object Windows.Forms.Label -Property @{Dock='Fill';Font=$smallFont;ForeColor=$script:Ui.Muted;AutoEllipsis=$true;UseMnemonic=$false}
$count=New-Object Windows.Forms.Label -Property @{Dock='Right';AutoSize=$true;Font=$smallFont;ForeColor=$script:Ui.Muted}
Add-NativeStack $tipRow @($count,$tip)
Add-NativeStack $postSide @($postHead,(New-NativeGap Top 6),$tipRow,(New-NativeGap Bottom 6),$out.Frame)
$resultGrid.Controls.Add($imageSide,0,0);$resultGrid.Controls.Add($postSide,2,0)
$tabs=$null;$tabsKey=''
# A row's own buttons rebuild the rows: the rebuild waits until their click is over.
function Request-SocialUpdate {[void]$form.BeginInvoke([Windows.Forms.MethodInvoker]{Update-Social})}

# ----- What the page's render functions do -----
function Get-SocialCurrentIndex {
    for($i=0;$i -lt $state.rows.Count;$i++){if($state.rows[$i].id -eq $state.current){return $i}}
    return -1
}
function Get-SocialRowOf($Control) {
    while($Control -and -not ($Control -is [ToolsHubNative.Row])){$Control=$Control.Parent}
    return $Control
}
# One row per product, as in Product Review: #, name, status, thumbnail, Xem / sửa, ×.
function Update-SocialRows {
    $rowsPanel.SuspendLayout()
    foreach($control in @($rowsPanel.Controls)){$control.Dispose()}
    $items=@()
    for($i=0;$i -lt $state.rows.Count;$i++){
        $row=$state.rows[$i]
        # Laid out at 600px wide and anchored, so the rows follow the list's width.
        $line=New-Object ToolsHubNative.Row -Property @{Dock='Top';Size='600,60';Tag=$row;Current=($row.id -eq $state.current)}
        $number=New-Object Windows.Forms.Label -Property @{Text="#$($i+1)";Location='10,20';Size='34,20';ForeColor=$script:Ui.Muted}
        $name=New-Object Windows.Forms.Label -Property @{Text=$row.name;Location='52,20';Size='184,20';Anchor='Top,Left,Right';AutoEllipsis=$true;UseMnemonic=$false}
        $scenes=0;foreach($source in $row.sources){$scenes+=$source.scenes}
        $statusText=if($row.sources.Count){"● $($row.sources.Count) ảnh gốc · $scenes ảnh"}else{'● Chưa có ảnh'}
        $rowStatus=New-Object Windows.Forms.Label -Property @{Text=$statusText;Location='244,20';Size='150,20';Anchor='Top,Right';AutoEllipsis=$true;ForeColor=$(if($row.sources.Count){[Drawing.Color]::FromArgb(0,100,0)}else{$script:Ui.Warn})}
        $thumb=New-Object Windows.Forms.PictureBox -Property @{Location='402,8';Size='44,44';Anchor='Top,Right';BackColor=[Drawing.SystemColors]::Control}
        if($row.sources.Count){$thumb.Image=Get-SocialPicture $row.sources[0].path 44}
        $open=New-NativeButton 'Xem / sửa';$open.Location='454,13';$open.Size='96,34';$open.Anchor='Top,Right'
        $remove=New-NativeButton '×';$remove.Location='558,13';$remove.Size='34,34';$remove.Anchor='Top,Right'
        $line.Controls.AddRange(@($number,$name,$rowStatus,$thumb,$open,$remove))
        foreach($control in @($line,$number,$name,$rowStatus,$thumb)){$control.Add_Click({param($sender) Set-SocialCurrent (Get-SocialRowOf $sender).Tag.id})}
        $open.Add_Click({param($sender) $row=(Get-SocialRowOf $sender).Tag;Set-SocialCurrent $row.id;Show-SocialEditor $row})
        $remove.Add_Click({param($sender) $state.rows.Remove((Get-SocialRowOf $sender).Tag);Request-SocialUpdate})
        $items+=$line;$items+=(New-NativeGap Top 4)
    }
    if($items.Count){Add-NativeStack $rowsPanel $items}
    $rowsPanel.ResumeLayout()
    $rowsPanel.Visible=[bool]$state.rows.Count
    $rowsBox.Message=$(if($state.rows.Count){''}else{'Bấm + Thêm sản phẩm để bắt đầu.'})
    foreach($control in $rowsPanel.Controls){if($control -is [ToolsHubNative.Row] -and $control.Current){$rowsPanel.ScrollControlIntoView($control)}}
}
function Set-SocialCurrent([string]$Id) {
    $state.current=$Id
    foreach($control in $rowsPanel.Controls){if($control -is [ToolsHubNative.Row]){$control.Current=($control.Tag.id -eq $Id)}}
    Update-SocialResult
}
function Update-SocialPlatforms {
    foreach($toggle in $platformGrid.Controls){$toggle.Pressed=($state.platforms -contains [string]$toggle.Tag)}
}
function Update-SocialResult {
    $index=Get-SocialCurrentIndex
    $row=if($index -ge 0){$state.rows[$index]}else{$null}
    $resultGroup.Heading=$(if($row){"Kết quả · #$($index+1) $($row.name)"}else{'Kết quả'})
    if($state.platforms -notcontains $state.tab){$state.tab=$state.platforms[0]}
    $platform=Get-SocialPlatform $state.tab
    # A tab per chosen platform, with its logo; made again only when the platforms change.
    if($script:tabsKey -ne ($state.platforms -join ',')){
        if($script:tabs){$script:tabs.Dispose()}
        $script:tabsKey=$state.platforms -join ','
        $script:tabs=New-NativeSeg @($state.platforms | ForEach-Object {@{Id=$_;Text=(Get-SocialPlatform $_).name;Image=$logos[$_].On}})
        $width=0;foreach($button in $script:tabs.Controls){$width=[Math]::Max($width,$button.Right)}
        $script:tabs.Dock='None';$script:tabs.Bounds=New-Object Drawing.Rectangle(0,0,$width,32)
        foreach($button in $script:tabs.Controls){$button.Add_Click({param($sender) $state.tab=[string]$sender.Tag;Update-SocialResult})}
        $postHead.Controls.Add($script:tabs)
    }
    Update-NativeSeg $script:tabs $state.tab
    $text=if($row){Get-SocialPost $row $state.tab $state.tone}else{''}
    $out.Text.Text=$text -replace '\r?\n',"`r`n"
    $tip.Text=$platform.tip
    $length=(New-Object Globalization.StringInfo($text)).LengthInTextElements
    $count.Text='{0} / {1} ký tự' -f $length.ToString('N0',$vi),([int]$platform.limit).ToString('N0',$vi)
    $count.ForeColor=$(if($length -gt $platform.limit){[Drawing.Color]::FromArgb(176,0,32)}else{$script:Ui.Muted})
    $copy.Enabled=[bool]$row
    # Each original image, then the bối cảnh it will give (waiting until Bắt đầu makes them).
    $tiles.SuspendLayout()
    foreach($control in @($tiles.Controls)){$control.Dispose()}
    if($row -and $row.sources.Count){
        foreach($source in $row.sources){
            $line=New-Object Windows.Forms.FlowLayoutPanel -Property @{AutoSize=$true;WrapContents=$false;Margin='0,0,0,10'}
            $origin=New-Object ToolsHubNative.Tile -Property @{Size='84,84';Border=[Drawing.Color]::Black;Margin='0,0,8,0';Picture=(Get-SocialPicture $source.path 84);Caption=[IO.Path]::GetFileName($source.path);Font=$smallFont}
            $arrow=New-Object Windows.Forms.Label -Property @{Text='→';AutoSize=$true;ForeColor=$script:Ui.Muted;Margin='0,32,8,0'}
            $line.Controls.AddRange(@($origin,$arrow))
            for($k=1;$k -le $source.scenes;$k++){$line.Controls.Add((New-Object ToolsHubNative.Tile -Property @{Size='84,84';Dashed=$true;Caption="Bối cảnh $k";Margin='0,0,8,0';Font=$smallFont}))}
            $tiles.Controls.Add($line)
        }
        $emptyTiles.Visible=$false;$tiles.Visible=$true
    } else {
        $tiles.Visible=$false;$emptyTiles.Visible=$true
        $emptyTiles.Message=$(if($row){'Thêm ảnh gốc ở Xem / sửa, rồi bấm Bắt đầu.'}else{'Thêm sản phẩm để xem ảnh và bài đăng ở đây.'})
    }
    $tiles.ResumeLayout()
}
function Update-Social {
    if(-not ($state.rows | Where-Object {$_.id -eq $state.current})){$state.current=$(if($state.rows.Count){$state.rows[0].id}else{''})}
    Update-SocialRows;Update-SocialPlatforms;Update-NativeSeg $toneSeg $state.tone;Update-SocialResult
    $status.Text="Sẵn sàng • $($state.rows.Count) sản phẩm"
}

# ----- Xem / sửa: the product's details and original images, like the page's dialog -----
function Show-SocialEditor($Row) {
    $draft=New-Object Collections.ArrayList
    if($Row){foreach($source in $Row.sources){[void]$draft.Add(@{path=$source.path;scenes=$source.scenes})}}
    $title=if($Row){"Sản phẩm #$($state.rows.IndexOf($Row)+1)"}else{'Thêm sản phẩm'}
    $dialog=New-Object Windows.Forms.Form -Property @{Text=$title;ClientSize='640,543';StartPosition='CenterParent';FormBorderStyle='FixedDialog';MinimizeBox=$false;MaximizeBox=$false;ShowInTaskbar=$false;Font=$script:NativeFont;BackColor=[Drawing.SystemColors]::Control;ForeColor=$script:Ui.Ink}
    $fields=@{}
    # Tên sản phẩm (2 parts) and Thương hiệu (1 part) side by side, then the rest one under another.
    foreach($field in @(
        @{Key='name';Label='Tên sản phẩm';X=16;Y=14;W=396},
        @{Key='brand';Label='Thương hiệu';X=424;Y=14;W=200},
        @{Key='link';Label='Link sản phẩm';X=16;Y=73;W=608},
        @{Key='points';Label='Điểm nổi bật (mỗi dòng một ý)';X=16;Y=132;W=608;H=72},
        @{Key='tags';Label='Hashtag (cách nhau bởi dấu cách)';X=16;Y=238;W=608})){
        $label=New-Object Windows.Forms.Label -Property @{Text=$field.Label;Location=(New-Object Drawing.Point($field.X,$field.Y));Size=(New-Object Drawing.Size($field.W,20));UseMnemonic=$false}
        $textBox=New-Object Windows.Forms.TextBox -Property @{Location=(New-Object Drawing.Point($field.X,($field.Y+22)));Width=$field.W;Text=$(if($Row){[string]$Row[$field.Key]}else{''})}
        if($field.H){$textBox.Multiline=$true;$textBox.AcceptsReturn=$true;$textBox.ScrollBars='Vertical';$textBox.Height=$field.H}
        $fields[$field.Key]=$textBox;$dialog.Controls.AddRange(@($label,$textBox))
    }
    $dialog.Controls.Add((New-Object Windows.Forms.Label -Property @{Text='Ảnh gốc (một sản phẩm có thể nhiều ảnh; mỗi ảnh ra nhiều bối cảnh)';Location='16,297';Size='608,20'}))
    $strip=New-Object Windows.Forms.FlowLayoutPanel -Property @{Location='16,319';Size='608,166';AutoScroll=$true;WrapContents=$false;AllowDrop=$true}
    $dialog.Controls.Add($strip)
    function Add-SocialSources([string[]]$Files) {
        foreach($file in $Files){if([IO.Path]::GetExtension($file) -match '^\.(png|jpe?g|webp)$'){[void]$draft.Add(@{path=$file;scenes=3})}}
        Update-SocialSources
    }
    # Each image: its tile with × to drop it, and how many bối cảnh it gives (1–6); then the dashed + Thêm ảnh tile.
    function Update-SocialSources {
        $strip.SuspendLayout()
        foreach($control in @($strip.Controls)){$control.Dispose()}
        foreach($source in $draft){
            $box=New-Object Windows.Forms.Panel -Property @{Size='112,142';Margin='0,0,10,0'}
            $tile=New-Object ToolsHubNative.Tile -Property @{Size='112,112';Picture=(Get-SocialPicture $source.path 112);Caption=[IO.Path]::GetFileName($source.path)}
            $drop=New-Object Windows.Forms.Button -Property @{Text='×';Location='86,4';Size='22,22';Tag=$source;Padding='0,0,0,0'}
            Set-FlatButton $drop
            $drop.Add_Click({param($sender) $draft.Remove($sender.Tag);[void]$dialog.BeginInvoke([Windows.Forms.MethodInvoker]{Update-SocialSources})})
            $tile.Controls.Add($drop)
            $number=New-Object Windows.Forms.NumericUpDown -Property @{Location='0,116';Size='52,24';Minimum=1;Maximum=6;Value=$source.scenes;Tag=$source}
            $number.Add_ValueChanged({param($sender) $sender.Tag.scenes=[int]$sender.Value})
            $caption=New-Object Windows.Forms.Label -Property @{Text='bối cảnh';Location='58,119';AutoSize=$true;ForeColor=$script:Ui.Muted;Font=$smallFont}
            $box.Controls.AddRange(@($tile,$number,$caption))
            $strip.Controls.Add($box)
        }
        $more=New-Object ToolsHubNative.Tile -Property @{Size='112,112';Dashed=$true;Clickable=$true;Caption="+`r`nThêm ảnh`r`nhoặc kéo thả";AllowDrop=$true}
        $more.Add_Click({
            $picker=New-Object Windows.Forms.OpenFileDialog -Property @{Filter='Ảnh|*.jpg;*.jpeg;*.png;*.webp';Multiselect=$true}
            try{if($picker.ShowDialog($dialog) -eq 'OK'){Add-SocialSources $picker.FileNames}}finally{$picker.Dispose()}
        })
        foreach($target in @($more)){
            $target.Add_DragEnter({param($sender,$eventArgs) if($eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$eventArgs.Effect='Copy';$sender.Lit=$true}})
            $target.Add_DragLeave({param($sender) $sender.Lit=$false})
            $target.Add_DragDrop({param($sender,$eventArgs) Add-SocialSources @($eventArgs.Data.GetData([Windows.Forms.DataFormats]::FileDrop))})
        }
        $strip.Controls.Add($more)
        $strip.ResumeLayout()
    }
    $strip.Add_DragEnter({param($sender,$eventArgs) if($eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$eventArgs.Effect='Copy'}})
    $strip.Add_DragDrop({param($sender,$eventArgs) Add-SocialSources @($eventArgs.Data.GetData([Windows.Forms.DataFormats]::FileDrop))})
    Update-SocialSources
    $warn=New-Object Windows.Forms.Label -Property @{Location='16,501';Size='370,20';ForeColor=$script:Ui.Warn}
    $save=New-NativeButton 'Lưu' -Primary;$save.Location='406,495';$save.Width=104
    $cancel=New-NativeButton 'Hủy';$cancel.Location='520,495';$cancel.Width=104;$cancel.DialogResult='Cancel'
    $save.Add_Click({
        if(-not $fields.name.Text.Trim()){$warn.Text='Điền tên sản phẩm';[void]$fields.name.Focus();return}
        $dialog.DialogResult='OK'
    })
    $dialog.Controls.AddRange(@($warn,$save,$cancel));$dialog.CancelButton=$cancel
    $dialog.Add_Shown({[void]$fields.name.Focus()})
    try {
        if($dialog.ShowDialog($form) -ne 'OK'){return}
        $target=if($Row){$Row}else{ConvertTo-SocialRow @{}}
        foreach($key in @('name','brand','link','points','tags')){$target[$key]=$fields[$key].Text}
        $target.sources=$draft
        if(-not $Row){[void]$state.rows.Add($target)}
        $state.current=$target.id
        Request-SocialUpdate
    } finally { $dialog.Dispose() }
}

# ----- Actions -----
$add.Add_Click({Show-SocialEditor $null})
$clear.Add_Click({
    if(-not $state.rows.Count){return}
    if([Windows.Forms.MessageBox]::Show($form,'Xóa tất cả sản phẩm?','Content MXH','YesNo','Question') -eq 'Yes'){$state.rows.Clear();Update-Social}
})
foreach($toggle in $platformGrid.Controls){
    $toggle.Add_Click({
        param($sender)
        $id=[string]$sender.Tag;$on=$state.platforms -contains $id
        if($on -and $state.platforms.Count -eq 1){Show-NativeToast $form 'Chọn ít nhất một nền tảng';return}
        $state.platforms=@($platformIds | Where-Object {($_ -eq $id -and -not $on) -or ($_ -ne $id -and $state.platforms -contains $_)})
        if(-not $on){$state.tab=$id}
        Update-SocialPlatforms;Update-SocialResult
    })
}
foreach($button in $toneSeg.Controls){$button.Add_Click({param($sender) $state.tone=[string]$sender.Tag;Update-NativeSeg $toneSeg $state.tone;Update-SocialResult})}
$note.Add_TextChanged({$state.note=$note.Text})
$run.Add_Click({
    if(-not $state.rows.Count){Show-NativeToast $form 'Thêm sản phẩm trước';return}
    for($i=0;$i -lt $state.rows.Count;$i++){if(-not $state.rows[$i].sources.Count){Show-NativeToast $form "Sản phẩm #$($i+1) chưa có ảnh gốc";return}}
    Show-NativeToast $form 'Tạo ảnh và bài đăng đang được làm, chưa dùng được'
})
$copy.Add_Click({if($out.Text.Text){[Windows.Forms.Clipboard]::SetText($out.Text.Text);Show-NativeToast $form ('Đã copy bài đăng '+(Get-SocialPlatform $state.tab).name)}})
$form.Add_FormClosed({
    Write-NativeState $statePath $state
    foreach($picture in $pictures.Values){if($picture){$picture.Dispose()}}
})
Update-Social
# Opened from the menu (hub/launch.ps1) the window is a page of the menu's window, which runs it.
if(-not $BuildOnly -and -not $global:ToolsHubHosted){Show-NativeToolWindow $shell $PSCommandPath}
