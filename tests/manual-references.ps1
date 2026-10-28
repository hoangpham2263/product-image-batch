. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $root 'src/ui/image-feedback.ps1')
. (Join-Path $root 'src/ui/manual-references.ps1')
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('manual-ref-'+[Guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $temp -Force|Out-Null
    $original=Join-Path $temp 'room.png';$bitmap=[Drawing.Bitmap]::new(64,48)
    try{$g=[Drawing.Graphics]::FromImage($bitmap);$g.Clear([Drawing.Color]::Tan);$g.Dispose();$bitmap.Save($original,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    $url='https://example.test/p/table';$otherUrl='https://example.test/p/other'
    $mapPath=Save-ManualReference $temp $url $original
    [void](Save-ManualReference $temp $otherUrl $original)
    $map=Read-ManualReferenceMap $mapPath
    Assert ($map.entries.Count -eq 2 -and -not $map.allow_library_fallback) 'Mappings or manual-only default lost.'
    $first=@($map.entries|Where-Object product_url -eq $url)[0]
    [IO.File]::WriteAllText($original,'source changed after attachment')
    Assert ((Get-BytesHash ([IO.File]::ReadAllBytes($first.file))) -eq $first.sha256) 'Attached image did not retain independent bytes.'
    $script:Config=@{ActiveProductUrl=$url;ManualReferences=[Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($map));PhotosPerImage=1}
    $script:Batch=@{Logs=$temp}
    $context=[pscustomobject]@{product='table';presentation='placed';source_categories=@('dining-tables')}
    $script:Verdict='FIT';$script:LibraryCalls=0
    function Test-ReferencePhoto($Photo,$Reference,$Context,$Role){Assert ($Photo -eq $first.file -and $Role -eq 'Scene') 'Wrong link image or role.';return $script:Verdict}
    function Select-Photo{$script:LibraryCalls++;return 'library-fallback.jpg'}
    $picked=@(Select-ProductReferences 'product.jpg' 'table' 'manual' $context)
    Assert ($picked.Count -eq 1 -and $picked[0] -eq $first.file -and $script:LibraryCalls -eq 0) 'Manual reference did not bypass random library selection.'
    function Test-ReferencePhoto {throw 'Manually attached photos must not trigger AI suitability QA.'}
    Assert ((Select-ProductReferences 'product.jpg' 'table' 'manual-no-qa' $context) -eq $first.file) 'User-selected photo was not used directly.'
    $script:Config.ActiveProductUrl='https://example.test/p/unattached';$script:Config.ManualReferences.allow_library_fallback=$false
    $rejected=$false;try{Select-ProductReferences 'product.jpg' 'table' 'missing-manual' $context|Out-Null}catch{$rejected=$true}
    Assert ($rejected -and $script:LibraryCalls -eq 0) 'Unattached URL borrowed another product image.'
    $script:Config.ManualReferences.allow_library_fallback=$true
    Assert ((Select-ProductReferences 'product.jpg' 'table' 'allowed-fallback' $context) -eq 'library-fallback.jpg') 'Explicit fallback did not work.'
    $editor=New-ProductQueueEditor $temp
    Set-ProductQueueUrls $editor @($url,$otherUrl)
    $view=New-Object Windows.Forms.Form -Property @{Size='1120,450';ShowInTaskbar=$false;StartPosition='Manual';Location='-32000,-32000'}
    $editor.Panel.Dock='Fill';$view.Controls.Add($editor.Panel)
    try{
        Assert ($editor.Rows.Count -eq 2 -and $editor.Rows[0].Url.Text -eq $url) 'Inline GUI lost per-link rows.'
        Assert ($editor.Rows[0].Preview.Image -and $editor.Rows[1].Preview.Image) 'Inline image thumbnails missing.'
        Assert (-not $editor.Fallback.Checked -and $editor.Rows[0].Preview.AllowDrop) 'Unexpected fallback default or missing inline drop target.'
        $editor.Rows[0].Url.Text='https://example.test/p/new-link'
        Assert (-not $editor.Rows[0].Preview.Image -and -not $editor.Rows[0].ImagePath) 'Changing a URL carried over the previous product reference.'
        $queue=Join-Path $temp 'urls.txt'
        $blocked=$false;try{Save-ProductQueueEditor $editor $queue -RequireReady}catch{$blocked=$true}
        Assert $blocked 'Start preflight accepted an unattached row.'
        Add-ProductQueueLinks $editor "https://example.test/p/third`nhttps://example.test/p/fourth`nhttps://example.test/p/third"
        Assert ($editor.Rows.Count -eq 4) 'Bulk paste lost URL pairs or added duplicate rows.'
        $editor.Rows[0].Url.Text=$url
        Assert ($editor.Rows[0].Preview.Image) 'Returning to a saved URL did not restore its own thumbnail.'
        Set-ProductQueueReference $editor $editor.Rows[2] $first.file
        Assert ($editor.Rows[2].ImagePath -and $editor.Rows[0].ImagePath -eq $first.file) 'Attaching a new row image replaced a different product pairing.'
        $fourthUrl=$editor.Rows[3].Url.Text;$editor.Rows[3].Url.Text=$url
        $blocked=$false;try{Save-ProductQueueEditor $editor $queue}catch{$blocked=$_.Exception.Message -match [regex]::Escape($url)}
        Assert $blocked 'Duplicate URL rows can overwrite each other reference mapping.'
        $editor.Rows[3].Url.Text=$fourthUrl
        $editor.Fallback.Checked=$true
        Save-ProductQueueEditor $editor $queue -RequireReady
        Assert (@(Get-Content -LiteralPath $queue).Count -eq 4 -and (Read-ManualReferenceMap $mapPath).allow_library_fallback) 'Inline queue did not persist its URLs/settings.'
        Assert ((Read-ManualReferenceMap $mapPath).source_library -eq 'drive') 'The library should default to Drive.'
        $editor.Library.SelectedIndex=1;Save-ProductQueueEditor $editor $queue
        Assert ((Read-ManualReferenceMap $mapPath).source_library -eq 'local') 'Choosing the local library was not saved.'
        $view.Show();$view.Refresh();$editor.Flow.ScrollControlIntoView($editor.Rows[3].Card)
        $editor.Rows[3].Card.Controls.Find('RemoveProduct',$true)[0].PerformClick()
        Assert ($editor.Rows.Count -eq 3 -and $editor.Rows[2].Number.Text -eq '#3') 'Removing an inline row changed the wrong pair or row numbering.'
        $view.Show();$view.Refresh()
        $shot=[Drawing.Bitmap]::new($view.Width,$view.Height)
        try{$view.DrawToBitmap($shot,[Drawing.Rectangle]::new(0,0,$shot.Width,$shot.Height));$shot.Save((Join-Path $TestWorkspaceRoot 'inline-queue-preview.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$shot.Dispose()}
    }finally{$view.Dispose()}
    [IO.File]::WriteAllText($first.file,'tampered snapshot');$script:Config.ActiveProductUrl=$url
    $rejected=$false;try{Select-ProductReferences 'product.jpg' 'table' 'changed-manual' $context|Out-Null}catch{$rejected=$true}
    Assert $rejected 'Changed manual snapshot was used without verification.'
    Write-Host 'PASS: per-URL image snapshots, serialized worker inputs, strict explicit selection, rejection without substitution and manual-reference UI.' -ForegroundColor Green
}finally{
    $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\')+'\'
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'manual-ref-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
