function Set-FeedbackPreview($Picture, [string]$Path) {
    if ($Picture.Image) { $Picture.Image.Dispose(); $Picture.Image=$null }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $stream = [IO.File]::OpenRead($Path)
    try { $loaded = [Drawing.Image]::FromStream($stream); try { $Picture.Image = [Drawing.Bitmap]::new($loaded) } finally { $loaded.Dispose() } } finally { $stream.Dispose() }
}

function New-ImageFeedbackDialog([string]$ProjectRoot, [string]$OutputRoot) {
    $state = @{FeedbackPath='';ApprovedImage='';Target=$null}
    $dialog = New-Object Windows.Forms.Form -Property @{Text='Kiểm tra ảnh, phản bác và bài học';Size='920,740';MinimumSize='920,740';StartPosition='CenterParent';Font=(New-Object Drawing.Font('Segoe UI',10))}
    $tabs = New-Object Windows.Forms.TabControl -Property @{Location='12,12';Size='880,676';Anchor='Top,Bottom,Left,Right'}
    $edit = New-Object Windows.Forms.TabPage -Property @{Text='Kiểm tra & làm lại'}
    $history = New-Object Windows.Forms.TabPage -Property @{Text='Bài học & lịch sử'}
    $tabs.TabPages.AddRange(@($edit,$history));$dialog.Controls.Add($tabs)
    $choices = New-Object Windows.Forms.ComboBox -Property @{Name='FeedbackImage';Location='12,12';Size='708,28';DropDownStyle='DropDownList';DisplayMember='Label'}
    $browse = New-Object Windows.Forms.Button -Property @{Text='Chọn ảnh…';Location='730,10';Size='124,30'}
    $productLabel=New-Object Windows.Forms.Label -Property @{Text='Sản phẩm gốc';Location='12,52';AutoSize=$true}
    $resultLabel=New-Object Windows.Forms.Label -Property @{Text='Ảnh cần kiểm tra';Location='448,52';Size='406,24';AutoEllipsis=$true}
    $productPreview=New-Object Windows.Forms.PictureBox -Property @{Name='ProductPreview';Location='12,78';Size='410,240';SizeMode='Zoom';BackColor=[Drawing.Color]::WhiteSmoke}
    $resultPreview=New-Object Windows.Forms.PictureBox -Property @{Name='ResultPreview';Location='448,78';Size='406,240';SizeMode='Zoom';BackColor=[Drawing.Color]::WhiteSmoke}
    $hint=New-Object Windows.Forms.Label -Property @{Text='Nêu rõ chỗ sai và kết quả cần sửa (ví dụ: thay cả ghế nệm bằng đúng ghế gỗ của sản phẩm).';Location='12,328';Size='842,26'}
    $text=New-Object Windows.Forms.TextBox -Property @{Name='RequestedChange';Multiline=$true;ScrollBars='Vertical';MaxLength=4000;Location='12,358';Size='842,106'}
    $remember=New-Object Windows.Forms.CheckBox -Property @{Name='RememberLesson';Text='Lưu bài học vào AGENTS.md';Checked=$true;Location='12,478';Size='400,28'}
    $scope=New-Object Windows.Forms.ComboBox -Property @{Name='LessonScope';Location='448,478';Size='406,28';DropDownStyle='DropDownList'}
    [void]$scope.Items.Add('Chỉ sản phẩm này');[void]$scope.Items.Add('Cả danh mục sản phẩm');$scope.SelectedIndex=0
    $save=New-Object Windows.Forms.Button -Property @{Text='Lưu phản hồi';Location='12,522';Size='160,36'}
    $retry=New-Object Windows.Forms.Button -Property @{Name='RetryImage';Text='Lưu và làm lại';Location='184,522';Size='180,36'}
    $deliver=New-Object Windows.Forms.Button -Property @{Name='ApproveAndExport';Text='Duyệt ảnh này & bàn giao';Location='376,522';Size='250,36'}
    $note=New-Object Windows.Forms.Label -Property @{Text='Làm lại dùng đúng ảnh sản phẩm và phòng đã lưu, tạo kết quả mới. Bản cũ được giữ lại.';Location='12,570';Size='842,48';ForeColor=[Drawing.Color]::DimGray}
    $edit.Controls.AddRange(@($choices,$browse,$productLabel,$resultLabel,$productPreview,$resultPreview,$hint,$text,$remember,$scope,$save,$retry,$deliver,$note))
    $deliver.Add_Click({
        if(-not $state.Target){[void][Windows.Forms.MessageBox]::Show($dialog,'Hãy chọn ảnh cần duyệt có bản lưu đầu vào hợp lệ.');return}
        $state.ApprovedImage=$state.Target.ImagePath;$dialog.DialogResult='OK';$dialog.Close()
    }.GetNewClosure())
    $loadTarget = {
        try {
            $state.Target=$null
            if (-not $choices.SelectedItem) { return }
            $target=Get-FeedbackTarget $choices.SelectedItem.ImagePath
            Set-FeedbackPreview $productPreview $target.ProductPath;Set-FeedbackPreview $resultPreview $target.ImagePath
            $state.Target=$target
            $resultLabel.Text=$target.Manifest.product
        } catch { $resultLabel.Text=$_.Exception.Message;Set-FeedbackPreview $productPreview '';Set-FeedbackPreview $resultPreview '' }
    }.GetNewClosure()
    $choices.Add_SelectedIndexChanged($loadTarget)
    $browse.Add_Click({
        $picker=New-Object Windows.Forms.OpenFileDialog -Property @{Filter='Ảnh kết quả (*.png)|*.png';Title='Chọn ảnh trong thư mục images của app'}
        if (Test-Path -LiteralPath $OutputRoot) { $picker.InitialDirectory=$OutputRoot }
        try { if ($picker.ShowDialog($dialog) -eq 'OK') { $index=$choices.Items.Add([pscustomobject]@{Label=$picker.FileName;ImagePath=$picker.FileName});$choices.SelectedIndex=$index } } finally { $picker.Dispose() }
    }.GetNewClosure())
    $save.Add_Click({
        try {
            if (-not $state.Target) { throw 'Hãy chọn ảnh có bản lưu đầu vào hợp lệ.' }
            $lessonScope=if($scope.SelectedIndex -eq 1){'category'}else{'product'}
            $path=Save-ImageFeedback $ProjectRoot $state.Target.ImagePath $text.Text $lessonScope $remember.Checked
            $text.Clear()
            [void][Windows.Forms.MessageBox]::Show($dialog,'Đã lưu phản hồi và lựa chọn bài học. Xem tab Bài học & lịch sử.','Đã lưu')
        } catch { [void][Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,'Chưa lưu được') }
    }.GetNewClosure())
    $retry.Add_Click({
        try {
            if (-not $state.Target) { throw 'Hãy chọn ảnh có bản lưu đầu vào hợp lệ.' }
            $lessonScope=if($scope.SelectedIndex -eq 1){'category'}else{'product'}
            $state.FeedbackPath=Save-ImageFeedback $ProjectRoot $state.Target.ImagePath $text.Text $lessonScope $remember.Checked
            $dialog.DialogResult='OK';$dialog.Close()
        } catch { [void][Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,'Chưa làm lại được') }
    }.GetNewClosure())
    $list=New-Object Windows.Forms.ListBox -Property @{Name='FeedbackHistory';Location='12,12';Size='842,170';DisplayMember='Label'}
    $details=New-Object Windows.Forms.TextBox -Property @{Name='FeedbackDetails';Location='12,194';Size='842,300';Multiline=$true;ReadOnly=$true;ScrollBars='Vertical'}
    $accept=New-Object Windows.Forms.Button -Property @{Text='Ảnh mới đã đúng';Location='12,516';Size='180,36'}
    $toggle=New-Object Windows.Forms.Button -Property @{Text='Bật/tắt bài học';Location='204,516';Size='180,36'}
    $open=New-Object Windows.Forms.Button -Property @{Text='Mở kết quả mới';Location='396,516';Size='180,36'}
    $resume=New-Object Windows.Forms.Button -Property @{Text='Chạy lại phản hồi này';Location='588,516';Size='266,36'}
    $history.Controls.AddRange(@($list,$details,$accept,$toggle,$open,$resume))
    $statusNames=@{saved='Đã lưu, chưa chạy';running='Đang làm lại';awaiting_review='Có ảnh mới, chờ bạn kiểm tra';accepted='Bạn đã xác nhận đúng';failed='Làm lại bị lỗi';stopped='Đã dừng'}
    $refresh={
        $list.Items.Clear();$details.Clear()
        $feedbackRoot=Join-Path $ProjectRoot 'workspace/feedback'
        if (-not (Test-Path -LiteralPath $feedbackRoot)) { return }
        foreach($folder in @(Get-ChildItem -LiteralPath $feedbackRoot -Directory | Sort-Object LastWriteTimeUtc -Descending)) {
            $path=Join-Path $folder.FullName 'feedback.json'
            if(Test-Path -LiteralPath $path) { try { $r=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json;[void]$list.Items.Add([pscustomobject]@{Label="$($r.created_at) • $($statusNames[$r.status]) • $($r.product)";Path=$path}) } catch { Write-Verbose $_ } }
        }
    }.GetNewClosure()
    $tabs.Add_SelectedIndexChanged({if($tabs.SelectedTab -eq $history){& $refresh}}.GetNewClosure())
    $list.Add_SelectedIndexChanged({
        if(-not $list.SelectedItem){return}
        try {
            $r=Get-Content -LiteralPath $list.SelectedItem.Path -Raw -Encoding UTF8|ConvertFrom-Json
            $r.remember=[bool]@(Read-AgentLessons (Join-Path $ProjectRoot 'AGENTS.md')|Where-Object id -eq $r.id).Count
            $details.Text="Sản phẩm: $($r.product_url)`r`nTrạng thái: $($statusNames[$r.status])`r`nPhạm vi: $($r.scope) • Dùng làm bài học: $($r.remember)`r`n`r`nYêu cầu sửa:`r`n$($r.requested_change)`r`n`r`nKết quả mới: $($r.result_folder)`r`nLỗi: $($r.error)`r`nPhản hồi trước: $($r.parent_feedback_id)"
        } catch {$details.Text=$_.Exception.Message}
    }.GetNewClosure())
    $accept.Add_Click({try{if(-not $list.SelectedItem){return};Set-ImageFeedbackStatus $list.SelectedItem.Path accepted;& $refresh}catch{[void][Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message)}}.GetNewClosure())
    $toggle.Add_Click({try{if(-not $list.SelectedItem){return};$path=$list.SelectedItem.Path;$r=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json;$enabled=[bool]@(Read-AgentLessons (Join-Path $ProjectRoot 'AGENTS.md')|Where-Object id -eq $r.id).Count;Set-ImageFeedbackRemember $ProjectRoot $path (-not $enabled);& $refresh}catch{[void][Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message)}}.GetNewClosure())
    $open.Add_Click({if($list.SelectedItem){$r=Get-Content -LiteralPath $list.SelectedItem.Path -Raw -Encoding UTF8|ConvertFrom-Json;if($r.result_folder -and (Test-Path -LiteralPath $r.result_folder)){Start-Process explorer.exe -ArgumentList ('"'+$r.result_folder+'"')}}}.GetNewClosure())
    $resume.Add_Click({
        try {
            if(-not $list.SelectedItem){return}
            $r=Get-Content -LiteralPath $list.SelectedItem.Path -Raw -Encoding UTF8|ConvertFrom-Json
            if($r.status -notin @('saved','failed','stopped')){throw 'Phản hồi này đang chạy hoặc đã có kết quả. Hãy chọn ảnh mới ở tab Kiểm tra & làm lại để phản bác tiếp.'}
            $state.FeedbackPath=$list.SelectedItem.Path;$dialog.DialogResult='OK';$dialog.Close()
        } catch {[void][Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message)}
    }.GetNewClosure())
    if(Test-Path -LiteralPath $OutputRoot){
        $photos=@(Get-ChildItem -LiteralPath $OutputRoot -Directory|Sort-Object Name -Descending|Select-Object -First 30|ForEach-Object{ $images=Join-Path $_.FullName 'images';if(Test-Path -LiteralPath $images){Get-ChildItem -LiteralPath $images -File -Filter '*.png'}}|Select-Object -First 200)
        foreach($photo in $photos){[void]$choices.Items.Add([pscustomobject]@{Label="$($photo.Directory.Parent.Name) / $($photo.Name)";ImagePath=$photo.FullName})}
        if($choices.Items.Count){$choices.SelectedIndex=0}
    }
    $dialog.Add_FormClosed({Set-FeedbackPreview $productPreview '';Set-FeedbackPreview $resultPreview ''}.GetNewClosure())
    return [pscustomobject]@{Form=$dialog;State=$state}
}

function Show-ImageFeedbackDialog($Owner, [string]$ProjectRoot, [string]$OutputRoot) {
    $view=New-ImageFeedbackDialog $ProjectRoot $OutputRoot
    try { [void]$view.Form.ShowDialog($Owner);return [pscustomobject]@{FeedbackPath=$view.State.FeedbackPath;ApprovedImage=$view.State.ApprovedImage} } finally { $view.Form.Dispose() }
}
