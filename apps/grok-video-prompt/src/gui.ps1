param([switch]$BuildOnly)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Text.UTF8Encoding]::new($false)
$toolRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $toolRoot '../../hub/native-window.ps1')
$shell=New-NativeToolWindow 'Grok Video Prompt' $toolRoot
$form=$shell.Form
$statePath=Join-Path $toolRoot 'workspace/windows-state.json'
$state=Read-NativeState $statePath ([pscustomobject]@{seconds='10';code='';product=''})
$json=& node (Join-Path $PSScriptRoot 'export-prompts.cjs')
if($LASTEXITCODE -ne 0){throw 'Không đọc được dữ liệu prompt.'}
$prompts=$json | ConvertFrom-Json
$layout=New-Object Windows.Forms.TableLayoutPanel -Property @{Dock='Fill';ColumnCount=2;RowCount=2}
[void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',62)))
[void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',38)))
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',290)))
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
$shell.Body.Controls.Add($layout)
$styleGroup=New-Object Windows.Forms.GroupBox -Property @{Text='Style';Dock='Fill';Padding='12,24,12,12'}
$durations=New-Object Windows.Forms.FlowLayoutPanel -Property @{Dock='Top';Height=42}
$styles=New-Object Windows.Forms.ListBox -Property @{Dock='Fill';DisplayMember='name';IntegralHeight=$false}
$styleGroup.Controls.Add($styles);$styleGroup.Controls.Add($durations)
$actionGroup=New-Object Windows.Forms.GroupBox -Property @{Text='Thao tác';Dock='Fill';Padding='12,24,12,12'}
$productLabel=New-Object Windows.Forms.Label -Property @{Text='Tên sản phẩm';Dock='Top';Height=28}
$product=New-Object Windows.Forms.TextBox -Property @{Dock='Top';Height=90;Multiline=$true;Text=[string]$state.product}
$copy=New-NativeButton 'Copy prompt' -Primary;$copy.Dock='Top'
$message=New-Object Windows.Forms.Label -Property @{Dock='Bottom';Height=36;ForeColor=$script:Ui.Muted}
$actionGroup.Controls.AddRange(@($message,$copy,$product,$productLabel))
$promptGroup=New-Object Windows.Forms.GroupBox -Property @{Text='Prompt';Dock='Fill';Padding='12,24,12,12'}
$output=New-Object Windows.Forms.TextBox -Property @{Dock='Fill';Multiline=$true;ReadOnly=$true;ScrollBars='Vertical';BackColor=[Drawing.Color]::White}
$promptGroup.Controls.Add($output)
$videoGroup=New-Object Windows.Forms.GroupBox -Property @{Text='Video mẫu';Dock='Fill';Padding='12,24,12,12'}
$videoStatus=New-Object Windows.Forms.Label -Property @{Dock='Top';Height=55;Text='Đang tải video mẫu…'}
$videoButtons=New-Object Windows.Forms.FlowLayoutPanel -Property @{Dock='Bottom';Height=42}
$play=New-NativeButton 'Phát';$pause=New-NativeButton 'Tạm dừng';$play.Enabled=$false;$pause.Enabled=$false
$videoButtons.Controls.AddRange(@($play,$pause))
$videoGroup.Controls.Add($videoStatus);$videoGroup.Controls.Add($videoButtons)
# Windows' native media stack, hosted in WinForms; no browser or HTML renderer.
Add-Type -AssemblyName PresentationFramework,WindowsFormsIntegration
$hostMedia=New-Object Windows.Forms.Integration.ElementHost -Property @{Dock='Fill'}
$media=New-Object Windows.Controls.MediaElement -Property @{LoadedBehavior='Manual';UnloadedBehavior='Stop';Stretch='Uniform';IsMuted=$true}
$hostMedia.Child=$media;$videoGroup.Controls.Add($hostMedia);$hostMedia.BringToFront()
$media.Add_MediaEnded({$media.Position=[TimeSpan]::Zero;$media.Play()})
$media.Add_MediaFailed({$videoStatus.Text='Không phát được video mẫu. Kiểm tra mạng hoặc định dạng video.'})
$play.Add_Click({$media.Play()});$pause.Add_Click({$media.Pause()})
[void]$layout.Controls.Add($styleGroup,0,0);[void]$layout.Controls.Add($actionGroup,1,0)
[void]$layout.Controls.Add($promptGroup,0,1);[void]$layout.Controls.Add($videoGroup,1,1)
$videoState=@{videos=@{};loaded=$false;failed=$false;task=$null}
function Update-GrokVideo {
    try { if($media.Source){$media.Close()} } catch { }; $play.Enabled=$false;$pause.Enabled=$false
    if(-not $videoState.loaded){$videoStatus.Text='Đang tải video mẫu…';return}
    if($videoState.failed){$videoStatus.Text='Chưa tải được video mẫu. Kiểm tra mạng rồi mở lại.';return}
    $video=$videoState.videos.([string]$state.code)
    if($video -and $video.url){$media.Source=[Uri]$video.url;$videoStatus.Text='Video mẫu';$play.Enabled=$true;$pause.Enabled=$true}
    else{$videoStatus.Text='Prompt này có video mẫu nhưng chưa được tải lên.'}
}
function Update-GrokPrompt {
    $selected=$styles.SelectedItem
    if($selected){$state.code=$selected.code;$output.Text=([string]$selected.prompt).Replace([string]$prompts.placeholder,$(if($product.Text.Trim()){$product.Text.Trim()}else{[string]$prompts.placeholder}))}
    else{$state.code='';$output.Text=''}
    $output.Text=$output.Text -replace '\r?\n',"`r`n"
    $state.product=$product.Text;$copy.Enabled=[bool]$selected
}
function Set-GrokDuration([string]$Seconds) {
    $state.seconds=$Seconds;$styles.Items.Clear()
    foreach($item in @($prompts.durations.$Seconds)){[void]$styles.Items.Add($item)}
    $index=0
    for($i=0;$i -lt $styles.Items.Count;$i++){if($styles.Items[$i].code -eq $state.code){$index=$i}}
    if($styles.Items.Count){$styles.SelectedIndex=$index}
    foreach($button in $durations.Controls){Set-FlatButton $button -Primary:($button.Tag -eq $Seconds)}
    Update-GrokPrompt;Update-GrokVideo
}
foreach($seconds in @('6','10','15')){
    $button=New-NativeButton ($seconds+'s ('+@($prompts.durations.$seconds).Count+')');$button.Tag=$seconds;$button.Width=100
    $button.Add_Click({param($sender) Set-GrokDuration ([string]$sender.Tag)});$durations.Controls.Add($button)
}
$styles.Add_SelectedIndexChanged({Update-GrokPrompt;Update-GrokVideo})
$product.Add_TextChanged({Update-GrokPrompt})
$copy.Add_Click({if(-not $product.Text.Trim()){$message.Text='Điền tên sản phẩm';$product.Focus();return};[Windows.Forms.Clipboard]::SetText($output.Text);$message.Text='Đã copy prompt'})
$client=New-Object Net.WebClient
$videoTimer=New-Object Windows.Forms.Timer -Property @{Interval=250}
$videoState.task=$null
$videoTimer.Add_Tick({
    if(-not $videoState.task -or -not $videoState.task.IsCompleted){return}
    $videoTimer.Stop();$videoState.loaded=$true
    try{$videoState.videos=($videoState.task.GetAwaiter().GetResult() | ConvertFrom-Json).videos}catch{$videoState.failed=$true}
    Update-GrokVideo
})
$form.Add_Shown({if(-not $BuildOnly){$videoState.task=$client.DownloadStringTaskAsync([Uri]'https://tools-hub-api.hoangpham2263.workers.dev/grok/videos');$videoTimer.Start()}})
$form.Add_FormClosed({Write-NativeState $statePath $state;$videoTimer.Stop();$videoTimer.Dispose();$client.Dispose();try {$media.Close()} catch { };$hostMedia.Dispose()})
Set-GrokDuration ([string]$state.seconds)
if(-not $BuildOnly){[void]$form.ShowDialog()}
