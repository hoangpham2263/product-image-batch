. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
. (Join-Path $root 'src/application/batch-import.ps1')
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $root 'src/ui/image-feedback.ps1')
. (Join-Path $root 'src/ui/manual-references.ps1')
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('bulk-dialog-'+[Guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Force -Path $temp|Out-Null
    Copy-Item -Recurse (Join-Path $root 'src') (Join-Path $temp 'src')
    $editor=New-ProductQueueEditor $temp
    $archive=if($env:PRODUCT_IMPORT_TEST_ZIP){$env:PRODUCT_IMPORT_TEST_ZIP}else{Join-Path $root '../../docs/product-import-sample.zip'}
    # Run the real event callbacks without a blocking modal window.
    $definition=(Get-Command Show-ProductQueueBulkDialog).Definition.Replace('[void]$dialog.ShowDialog($Editor.Panel.FindForm())','& $probe $dialog')
    $probe={param($dialog)
        $dialog.Show()
        $text=$dialog.Controls.Find('BulkUrls',$true)[0]
        $buttons=@($dialog.Controls|Where-Object {$_ -is [Windows.Forms.Button]})
        $save=$buttons|Where-Object {$_.Location.Y -eq 436 -and $_.Width -eq 110}
        $pick=$dialog.Controls.Find('PickImportFile',$true)[0]
        Assert ($pick.Bottom -lt $text.Top -and $pick.Right -le $dialog.ClientSize.Width-16) 'File picker is clipped or overlaps the text box.'
        foreach($other in $dialog.Controls){if($other -ne $pick){Assert (-not $pick.Bounds.IntersectsWith($other.Bounds)) 'Another control covers the picker border.'}}
        Assert ($pick.FlatStyle -eq 'Standard' -and $pick.UseVisualStyleBackColor) 'Keep the existing native button style.'
        $preferred=$pick.GetPreferredSize([Drawing.Size]::Empty)
        Assert ($pick.Width -ge $preferred.Width -and $pick.Height -ge $preferred.Height) 'Picker text does not fit its button.'
        $shot=[Drawing.Bitmap]::new($dialog.Width,$dialog.Height)
        try{$dialog.DrawToBitmap($shot,[Drawing.Rectangle]::new(0,0,$shot.Width,$shot.Height));$shot.Save((Join-Path $TestWorkspaceRoot 'bulk-dialog-preview.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$shot.Dispose()}
        $save.PerformClick()
        $data=New-Object Windows.Forms.DataObject
        $data.SetData([Windows.Forms.DataFormats]::FileDrop,[string[]]@($archive))
        $event=New-Object Windows.Forms.DragEventArgs($data,0,0,0,[Windows.Forms.DragDropEffects]::Copy,[Windows.Forms.DragDropEffects]::Copy)
        $method=[Windows.Forms.Control].GetMethod('OnDragDrop',[Reflection.BindingFlags]'Instance,NonPublic')
        [void]$method.Invoke($text,@($event.PSObject.BaseObject))
        Assert (@($text.Lines|Where-Object { $_.Trim() }).Count -eq 4) ("Sample rows: $($text.Lines.Count). " + (($dialog.Controls | ForEach-Object Text) -join " | "))
        $save.PerformClick()
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        while(-not $save.Enabled -and [DateTime]::UtcNow -lt $deadline){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 50}
        Assert ($save.Enabled -and $editor.Rows.Count -eq 2) ("Import rows=$($editor.Rows.Count): " + (($dialog.Controls | ForEach-Object Text) -join " | "))
        $map=Read-ManualReferenceMap $editor.MapPath
        $products=@($map.entries|ForEach-Object {Get-ManualProducts $_})
        $reviews=@($products|ForEach-Object {$_.scenes})
        Assert ($products.Count -eq 3 -and $reviews.Count -eq 4) 'Sample image counts or pairings are wrong.'
    }
    & ([scriptblock]::Create($definition)) $editor
    Write-Host 'PASS: Windows bulk dialog callbacks import the sample ZIP with separate CSV lines and image pairings.'
}finally{
    if($editor){$editor.Panel.Dispose()}
    $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\')+'\'
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'bulk-dialog-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
