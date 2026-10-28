# Check every result next to its product photo, then write the final CSV.
function New-BatchReviewRow($View,$Item) {
    $ui=$script:Ui
    $row=New-Object Windows.Forms.Panel -Property @{Size='880,176';Margin='4,4,4,4';BackColor=$ui.Surface;BorderStyle='FixedSingle'}
    $product=New-Object Windows.Forms.PictureBox -Property @{Location='8,8';Size='160,160';SizeMode='Zoom';BackColor=[Drawing.Color]::WhiteSmoke;Cursor='Hand'}
    $result=New-Object Windows.Forms.PictureBox -Property @{Location='176,8';Size='160,160';SizeMode='Zoom';BackColor=[Drawing.Color]::WhiteSmoke;Cursor='Hand'}
    if($Item.ProductPath -and (Test-Path -LiteralPath $Item.ProductPath)){$product.Image=New-ThumbnailImage $Item.ProductPath 160}
    if(Test-Path -LiteralPath $Item.ImagePath){$result.Image=New-ThumbnailImage $Item.ImagePath 160}
    foreach($pair in @(@($product,$Item.ProductPath),@($result,$Item.ImagePath))){$p=$pair[1];if($p){$pair[0].Add_Click({Start-Process -FilePath $p}.GetNewClosure())}}
    $title=New-Object Windows.Forms.Label -Property @{Text="$($Item.Id)";Location='348,10';Size='516,22';AutoEllipsis=$true;Font=(New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold))}
    $body=New-Object Windows.Forms.Label -Property @{Text=[string]$Item.Row.body;Location='348,36';Size='516,84';AutoEllipsis=$true;ForeColor=$ui.Muted}
    $ok=New-Object Windows.Forms.Button -Property @{Text='Đạt';Location='348,128';Size='120,36'}
    $bad=New-Object Windows.Forms.Button -Property @{Text='Chưa đạt';Location='476,128';Size='120,36'}
    $paint={
        foreach($b in @($ok,$bad)){$b.FlatStyle='Standard';$b.UseVisualStyleBackColor=$true}
        if($Item.Decision -eq 'ok'){$ok.FlatStyle='Flat';$ok.BackColor=$ui.Accent;$ok.ForeColor=[Drawing.Color]::White;$row.BackColor=[Drawing.Color]::FromArgb(236,246,239)}
        elseif($Item.Decision -eq 'bad'){$bad.FlatStyle='Flat';$bad.BackColor=$ui.Error;$bad.ForeColor=[Drawing.Color]::White;$row.BackColor=[Drawing.Color]::FromArgb(250,236,236)}
        else{$row.BackColor=$ui.Surface}
    }.GetNewClosure()
    $decide={param($value) $next=if($Item.Decision -eq $value){''}else{$value};Set-BatchReviewDecision $View.BatchDir $Item.Id $next;$Item.Decision=$next;& $paint;& $View.Refresh}.GetNewClosure()
    $ok.Add_Click({& $decide 'ok'}.GetNewClosure());$bad.Add_Click({& $decide 'bad'}.GetNewClosure())
    & $paint
    $row.Controls.AddRange(@($product,$result,$title,$body,$ok,$bad))
    return $row
}

function New-BatchReviewDialog([string]$OutputRoot,[string]$BatchDir='') {
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Duyệt kết quả';Size='940,760';MinimumSize='940,500';StartPosition='CenterParent';Font=(New-Object Drawing.Font('Segoe UI',10))}
    $batches=New-Object Windows.Forms.ComboBox -Property @{Location='12,12';Size='600,28';DropDownStyle='DropDownList';DisplayMember='Label';Anchor='Top,Left'}
    $hint=New-Object Windows.Forms.Label -Property @{Text='Bấm ảnh để xem lớn. Ảnh chưa đạt sửa ở Kiểm tra ảnh / Làm lại.';Location='12,46';Size='900,22';ForeColor=$script:Ui.Muted}
    $flow=New-Object Windows.Forms.FlowLayoutPanel -Property @{Location='12,72';Size='900,580';AutoScroll=$true;FlowDirection='TopDown';WrapContents=$false;Anchor='Top,Bottom,Left,Right'}
    $status=New-Object Windows.Forms.Label -Property @{Location='12,668';Size='560,36';TextAlign='MiddleLeft';Anchor='Bottom,Left'}
    $export=New-Object Windows.Forms.Button -Property @{Text='Xuất file cuối';Location='732,664';Size='180,40';Anchor='Bottom,Right'}
    Set-FlatButton $export -Primary
    $dialog.Controls.AddRange(@($batches,$hint,$flow,$status,$export))
    $view=[pscustomobject]@{Form=$dialog;BatchDir='';Items=@();Refresh=$null}
    $view.Refresh={
        $items=@($view.Items);$done=@($items|Where-Object Decision).Count;$good=@($items|Where-Object Decision -eq 'ok').Count
        $status.Text="Đã duyệt $done/$($items.Count) • Đạt $good • Chưa đạt $($done-$good)"
        $export.Enabled=$items.Count -gt 0 -and $done -eq $items.Count -and $good -gt 0
    }.GetNewClosure()
    $load={
        foreach($c in @($flow.Controls)){foreach($p in @($c.Controls|Where-Object{$_ -is [Windows.Forms.PictureBox]})){if($p.Image){$p.Image.Dispose()}};$c.Dispose()}
        $flow.Controls.Clear()
        if(-not $batches.SelectedItem){$view.Items=@();& $view.Refresh;return}
        $view.BatchDir=$batches.SelectedItem.Path
        $view.Items=@(Get-BatchReview $view.BatchDir)
        $flow.SuspendLayout()
        foreach($item in $view.Items){$flow.Controls.Add((New-BatchReviewRow $view $item))}
        $flow.ResumeLayout()
        & $view.Refresh
    }.GetNewClosure()
    $batches.Add_SelectedIndexChanged($load)
    $export.Add_Click({
        try{$path=Export-ReviewedCsv $view.BatchDir;[void][Windows.Forms.MessageBox]::Show($dialog,"Đã xuất: $path",'Xong');Start-Process explorer.exe -ArgumentList ('/select,"'+$path+'"')}
        catch{[void][Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,'Chưa xuất được')}
    }.GetNewClosure())
    if(Test-Path -LiteralPath $OutputRoot){
        foreach($dir in @(Get-ChildItem -LiteralPath $OutputRoot -Directory|Where-Object{Test-Path -LiteralPath (Join-Path $_.FullName 'results.json')}|Sort-Object Name -Descending|Select-Object -First 30)){
            $label=$dir.Name+$(if(Test-Path -LiteralPath (Join-Path $dir.FullName 'loox_import_final.csv')){'  • đã xuất'}else{''})
            $index=$batches.Items.Add([pscustomobject]@{Label=$label;Path=$dir.FullName})
            if($BatchDir -and $dir.FullName -eq (Get-Item -LiteralPath $BatchDir -ErrorAction SilentlyContinue).FullName){$batches.SelectedIndex=$index}
        }
        if($batches.Items.Count -and $batches.SelectedIndex -lt 0){$batches.SelectedIndex=0}
    }
    & $view.Refresh
    return $view
}

function Show-BatchReviewDialog($Owner,[string]$OutputRoot,[string]$BatchDir='') {
    $view=New-BatchReviewDialog $OutputRoot $BatchDir
    try{[void]$view.Form.ShowDialog($Owner)}finally{$view.Form.Dispose()}
}
