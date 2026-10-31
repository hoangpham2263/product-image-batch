param([switch]$BuildOnly)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $toolRoot '../../hub/native-window.ps1')
. (Join-Path $PSScriptRoot 'model.ps1')
$shell=New-NativeToolWindow 'Content MXH' $toolRoot;$form=$shell.Form
$statePath=Join-Path $toolRoot 'workspace/windows-state.json'
$state=Read-NativeState $statePath ([pscustomobject]@{rows=@();tone='story';note='';platforms=@('facebook','instagram')})
$layout=New-Object Windows.Forms.TableLayoutPanel -Property @{Dock='Fill';ColumnCount=2;RowCount=3}
[void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',62)));[void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',38)))
foreach($height in @(285,64)){[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height)))}
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
$shell.Body.Controls.Add($layout)
$queueGroup=New-Object Windows.Forms.GroupBox -Property @{Text='Sản phẩm & ảnh';Dock='Fill';Padding='12,24,12,12'}
$actions=New-Object Windows.Forms.FlowLayoutPanel -Property @{Dock='Top';Height=42}
$add=New-NativeButton '+ Thêm sản phẩm' -Primary;$clear=New-NativeButton 'Xóa tất cả';$edit=New-NativeButton 'Xem / sửa';$remove=New-NativeButton 'Bỏ sản phẩm'
$actions.Controls.AddRange(@($add,$clear,$edit,$remove))
$rows=New-Object Windows.Forms.ListView -Property @{Dock='Fill';View='Details';FullRowSelect=$true;MultiSelect=$false;HideSelection=$false}
[void]$rows.Columns.Add('#',36);[void]$rows.Columns.Add('Sản phẩm',270);[void]$rows.Columns.Add('Trạng thái',210)
$queueGroup.Controls.Add($rows);$queueGroup.Controls.Add($actions)
$settingsGroup=New-Object Windows.Forms.GroupBox -Property @{Text='Thao tác';Dock='Fill';Padding='12,24,12,12'}
$settings=New-Object Windows.Forms.TableLayoutPanel -Property @{Dock='Fill';ColumnCount=1;RowCount=5}
$platforms=New-Object Windows.Forms.CheckedListBox -Property @{Dock='Fill';CheckOnClick=$true;Height=85;DisplayMember='name'}
foreach($platform in $script:SocialPlatforms){[void]$platforms.Items.Add([pscustomobject]$platform,($state.platforms -contains $platform.id))}
$tone=New-Object Windows.Forms.ComboBox -Property @{Dock='Fill';DropDownStyle='DropDownList'}
[void]$tone.Items.AddRange(@('Kể chuyện','Ngắn gọn','Bán hàng'));$tone.SelectedIndex=@('story','short','sale').IndexOf([string]$state.tone);if($tone.SelectedIndex -lt 0){$tone.SelectedIndex=0}
$note=New-Object Windows.Forms.TextBox -Property @{Dock='Fill';Multiline=$true;Text=[string]$state.note}
$settings.Controls.Add((New-Object Windows.Forms.Label -Property @{Text='Đăng lên';AutoSize=$true}),0,0)
$settings.Controls.Add($platforms,0,1);$settings.Controls.Add($tone,0,2)
$settings.Controls.Add((New-Object Windows.Forms.Label -Property @{Text='Lời nhắn cho AI';AutoSize=$true}),0,3);$settings.Controls.Add($note,0,4)
$settingsGroup.Controls.Add($settings)
$runPanel=New-Object Windows.Forms.FlowLayoutPanel -Property @{Dock='Fill';Padding='10,10,0,0'}
$run=New-NativeButton 'Bắt đầu' -Primary;$stop=New-NativeButton 'Dừng';$stop.Enabled=$false
$status=New-Object Windows.Forms.Label -Property @{AutoSize=$true;Margin='8,8,0,0'}
$runPanel.Controls.AddRange(@($run,$stop,$status))
$resultGroup=New-Object Windows.Forms.GroupBox -Property @{Text='Kết quả';Dock='Fill';Padding='12,24,12,12'}
$results=New-Object Windows.Forms.SplitContainer -Property @{Dock='Fill';SplitterDistance=400}
$sources=New-Object Windows.Forms.ListBox -Property @{Dock='Fill';IntegralHeight=$false}
$sources.DrawMode='OwnerDrawFixed';$sources.ItemHeight=96
$sources.Add_DrawItem({param($sender,$eventArgs)
    $eventArgs.DrawBackground();if($eventArgs.Index -lt 0){return}
    $source=$sources.Items[$eventArgs.Index];$bounds=$eventArgs.Bounds
    if(Test-Path -LiteralPath $source.path){
        $image=$null
        try{$image=[Drawing.Image]::FromFile($source.path);$eventArgs.Graphics.DrawImage($image,(New-Object Drawing.Rectangle(($bounds.X+4),($bounds.Y+4),84,84)))}catch{}finally{if($image){$image.Dispose()}}
    }
    $text=[IO.Path]::GetFileName($source.path)+"`n→ "+$source.scenes+' bối cảnh (chưa tạo)'
    [Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics,$text,$sources.Font,(New-Object Drawing.Rectangle(($bounds.X+96),($bounds.Y+8),([Math]::Max(1,$bounds.Width-104)),80)),$eventArgs.ForeColor,[Windows.Forms.TextFormatFlags]'WordBreak,EndEllipsis')
    $eventArgs.DrawFocusRectangle()
})
$results.Panel1.Controls.Add($sources)
$form.Add_Shown({$results.SplitterDistance=[int]($results.ClientSize.Width*0.45)})
$tabs=New-Object Windows.Forms.FlowLayoutPanel -Property @{Dock='Top';Height=40}
$copy=New-NativeButton 'Copy bài đăng';$copy.Dock='Bottom'
$output=New-Object Windows.Forms.TextBox -Property @{Dock='Fill';Multiline=$true;ReadOnly=$true;BackColor=[Drawing.Color]::White;ScrollBars='Vertical'}
$tip=New-Object Windows.Forms.Label -Property @{Dock='Bottom';Height=42}
$results.Panel2.Controls.AddRange(@($output,$tip,$copy,$tabs));$resultGroup.Controls.Add($results)
[void]$layout.Controls.Add($queueGroup,0,0);[void]$layout.Controls.Add($settingsGroup,1,0)
[void]$layout.Controls.Add($runPanel,0,1);$layout.SetColumnSpan($runPanel,2)
[void]$layout.Controls.Add($resultGroup,0,2);$layout.SetColumnSpan($resultGroup,2)
$view=@{tab='facebook';rendering=$false}
function Get-SocialSelected {if($rows.SelectedItems.Count){return $rows.SelectedItems[0].Tag};return $null}
function Update-SocialResult {
    $row=Get-SocialSelected;$tabs.Controls.Clear();$sources.Items.Clear()
    $chosen=@($platforms.CheckedItems)
    if(-not ($chosen.id -contains $view.tab)){$view.tab=$chosen[0].id}
    foreach($platform in $chosen){
        $button=New-NativeButton $platform.name;$button.Width=85;$button.Tag=$platform.id;Set-FlatButton $button -Primary:($view.tab -eq $platform.id)
        $button.Add_Click({param($sender)$view.tab=$sender.Tag;Update-SocialResult});$tabs.Controls.Add($button)
    }
    $state.tone=@('story','short','sale')[$tone.SelectedIndex];$state.note=$note.Text;$state.platforms=@($chosen.id)
    $output.Text=if($row){Get-SocialPost $row $view.tab $state.tone}else{''}
    $platform=@($script:SocialPlatforms | Where-Object id -eq $view.tab)[0]
    $tip.Text=$platform.tip+"`r`n"+$output.Text.Length+' / '+$platform.limit+' ký tự'
    $tip.ForeColor=if($output.Text.Length -gt $platform.limit){[Drawing.Color]::Firebrick}else{$script:Ui.Muted}
    $copy.Enabled=[bool]$row
    if($row){foreach($source in @($row.sources)){[void]$sources.Items.Add($source)}}
}
function Update-SocialRows {
    $view.rendering=$true;$selected=Get-SocialSelected;$rows.Items.Clear();$i=0
    foreach($row in @($state.rows)){
        $i++;$item=New-Object Windows.Forms.ListViewItem([string]$i);[void]$item.SubItems.Add([string]$row.name)
        $count=@($row.sources).Count;[void]$item.SubItems.Add($(if($count){"$count ảnh gốc"}else{'Chưa có ảnh'}));$item.Tag=$row;[void]$rows.Items.Add($item)
        if($selected -and $row.id -eq $selected.id){$item.Selected=$true}
    }
    if($rows.Items.Count -and -not $rows.SelectedItems.Count){$rows.Items[0].Selected=$true}
    $status.Text="Sẵn sàng • $i sản phẩm";$view.rendering=$false;Update-SocialResult
}
function Show-SocialEditor($Row) {
    $draft=if($Row){$Row | ConvertTo-Json -Depth 10 | ConvertFrom-Json}else{[pscustomobject]@{id=[Guid]::NewGuid().ToString('N');name='';brand='';link='';points='';tags='';sources=@()}}
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Sản phẩm';Size='680,640';StartPosition='CenterParent';Font=$form.Font;MinimizeBox=$false;MaximizeBox=$false}
    $fields=@{};$y=16
    foreach($field in @(@('name','Tên sản phẩm'),@('brand','Thương hiệu'),@('link','Link sản phẩm'),@('points','Điểm nổi bật (mỗi dòng một ý)'),@('tags','Hashtag (cách nhau bởi dấu cách)'))){
        $label=New-Object Windows.Forms.Label -Property @{Text=$field[1];Location=(New-Object Drawing.Point(16,$y));Size='610,22'};$y+=24
        $input=New-Object Windows.Forms.TextBox -Property @{Text=[string]$draft.($field[0]);Location=(New-Object Drawing.Point(16,$y));Width=620;Anchor='Top,Left,Right'}
        if($field[0] -eq 'points'){$input.Multiline=$true;$input.Height=62}
        $fields[$field[0]]=$input;$dialog.Controls.AddRange(@($label,$input));$y+=$input.Height+6
    }
    $sourceGrid=New-Object Windows.Forms.DataGridView -Property @{Location=(New-Object Drawing.Point(16,$y));Size='620,100';AllowUserToAddRows=$false;AutoSizeColumnsMode='Fill';SelectionMode='FullRowSelect';MultiSelect=$false}
    $sourceGrid.AllowDrop=$true
    $sourceGrid.Add_DragEnter({param($sender,$eventArgs)if($eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$eventArgs.Effect='Copy'}})
    $sourceGrid.Add_DragDrop({param($sender,$eventArgs)foreach($file in $eventArgs.Data.GetData([Windows.Forms.DataFormats]::FileDrop)){if([IO.Path]::GetExtension($file) -match '^\.(png|jpe?g|webp)$'){[void]$sourceGrid.Rows.Add($file,'3')}}})
    [void]$sourceGrid.Columns.Add('path','Ảnh gốc');[void]$sourceGrid.Columns.Add('scenes','Số bối cảnh (1–6)');$sourceGrid.Columns[0].ReadOnly=$true
    foreach($source in @($draft.sources)){[void]$sourceGrid.Rows.Add([string]$source.path,[string]$source.scenes)}
    $dialog.Controls.Add($sourceGrid);$y+=104
    $pick=New-NativeButton '+ Thêm ảnh';$pick.Location=New-Object Drawing.Point(16,$y)
    $drop=New-NativeButton 'Bỏ ảnh';$drop.Location=New-Object Drawing.Point(154,$y)
    $pick.Add_Click({$picker=New-Object Windows.Forms.OpenFileDialog -Property @{Filter='Ảnh|*.jpg;*.jpeg;*.png;*.webp';Multiselect=$true};try{if($picker.ShowDialog($dialog) -eq 'OK'){foreach($file in $picker.FileNames){[void]$sourceGrid.Rows.Add($file,'3')}}}finally{$picker.Dispose()}})
    $drop.Add_Click({if($sourceGrid.SelectedRows.Count){$sourceGrid.Rows.Remove($sourceGrid.SelectedRows[0])}})
    $save=New-NativeButton 'Lưu' -Primary;$save.Location=New-Object Drawing.Point(350,($y+42))
    $cancel=New-NativeButton 'Hủy';$cancel.Location=New-Object Drawing.Point(490,($y+42));$cancel.DialogResult='Cancel'
    $save.Add_Click({
        if(-not $fields.name.Text.Trim()){$fields.name.Focus();return}
        $draftSources=@()
        foreach($gridRow in $sourceGrid.Rows){$n=0;if(-not [int]::TryParse([string]$gridRow.Cells[1].Value,[ref]$n) -or $n -lt 1 -or $n -gt 6){[void][Windows.Forms.MessageBox]::Show($dialog,'Số bối cảnh phải từ 1 đến 6.');return};$draftSources+=@{path=[string]$gridRow.Cells[0].Value;scenes=$n}}
        foreach($key in $fields.Keys){$draft.$key=$fields[$key].Text};$draft.sources=$draftSources
        $dialog.DialogResult='OK';$dialog.Close()
    })
    $dialog.Controls.AddRange(@($pick,$drop,$save,$cancel));$dialog.Height=$y+130;$dialog.CancelButton=$cancel
    try{if($dialog.ShowDialog($form) -eq 'OK'){
        if($Row){$state.rows=@($state.rows | ForEach-Object {if($_.id -eq $Row.id){$draft}else{$_}})}else{$state.rows=@($state.rows)+@($draft)}
        Update-SocialRows
    }}finally{$dialog.Dispose()}
}
$add.Add_Click({Show-SocialEditor $null});$edit.Add_Click({$row=Get-SocialSelected;if($row){Show-SocialEditor $row}})
$rows.Add_DoubleClick({$edit.PerformClick()})
$remove.Add_Click({$row=Get-SocialSelected;if($row){$state.rows=@($state.rows | Where-Object id -ne $row.id);Update-SocialRows}})
$clear.Add_Click({if($state.rows.Count -and [Windows.Forms.MessageBox]::Show($form,'Xóa tất cả sản phẩm?','Content MXH','YesNo') -eq 'Yes'){$state.rows=@();Update-SocialRows}})
$rows.Add_SelectedIndexChanged({if(-not $view.rendering){Update-SocialResult}})
$tone.Add_SelectedIndexChanged({Update-SocialResult});$note.Add_TextChanged({$state.note=$note.Text})
$platformTimer=New-Object Windows.Forms.Timer -Property @{Interval=1}
$platformTimer.Add_Tick({$platformTimer.Stop();Update-SocialResult})
$platforms.Add_ItemCheck({param($sender,$eventArgs)if($eventArgs.NewValue -eq 'Unchecked' -and $platforms.CheckedItems.Count -eq 1){$eventArgs.NewValue='Checked'};$platformTimer.Start()})
$run.Add_Click({if(-not $state.rows.Count){$status.Text='Thêm sản phẩm trước';return};foreach($row in $state.rows){if(-not @($row.sources).Count){$status.Text='Sản phẩm '+$row.name+' chưa có ảnh gốc';return}};$status.Text='Tạo ảnh và bài đăng đang được làm, chưa dùng được'})
$copy.Add_Click({if($output.Text){[Windows.Forms.Clipboard]::SetText($output.Text);$status.Text='Đã copy bài đăng'}})
$form.Add_FormClosed({Write-NativeState $statePath $state;$platformTimer.Stop();$platformTimer.Dispose()})
Update-SocialRows
if(-not $BuildOnly){[void]$form.ShowDialog()}
