# Grok Video Prompt on Windows: the macOS page (ui/index.html) in WinForms, with the same data and sample videos.
# Left: Style (length, then the styles) and the Prompt; right (400px): Thao tác (product name, Copy prompt) and the
# chosen style's Video mẫu.
param([switch]$BuildOnly)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $toolRoot '../../hub/native-window.ps1')
$shell=New-NativeToolWindow 'Grok Video Prompt' $toolRoot
$form=$shell.Form
$statePath=Join-Path $toolRoot 'workspace/windows-state.json'

# The prompts of the macOS page: data/prompts.js plus the demo fill (data/demo-prompts.js), run by Node
# (src/export-prompts.cjs; Cấu hình installs Node). Without Node, data/prompts.js alone, read as JSON.
function Get-GrokPrompts {
    $node=@((Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),(Join-Path $env:ProgramFiles 'nodejs\node.exe')) |
        Where-Object {$_ -and (Test-Path -LiteralPath $_)} | Select-Object -First 1
    if($node){
        $previous=[Console]::OutputEncoding;$json=$null
        try{[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false);$json=(& $node (Join-Path $PSScriptRoot 'export-prompts.cjs')) -join "`n"}catch{$json=$null}
        finally{try{[Console]::OutputEncoding=$previous}catch{}}
        if($LASTEXITCODE -eq 0 -and $json){try{return $json | ConvertFrom-Json}catch{}}
    }
    $source=[IO.File]::ReadAllText((Join-Path $toolRoot 'data/prompts.js'),[Text.Encoding]::UTF8)
    $start=$source.IndexOf('{',$source.IndexOf('PROMPTS'))
    return $source.Substring($start,$source.LastIndexOf('}')-$start+1) | ConvertFrom-Json
}
$prompts=Get-GrokPrompts
$durationIds=@($prompts.durations.PSObject.Properties | ForEach-Object {$_.Name})
function Get-GrokStyles([string]$Seconds) {return @($prompts.durations.$Seconds | Where-Object {$_})}

$state=@{seconds='10';code='';product=''}
$saved=Read-NativeState $statePath $null
if($saved){foreach($key in @('seconds','code','product')){if($null -ne $saved.$key){$state[$key]=[string]$saved.$key}}}
if($durationIds -notcontains $state.seconds){$state.seconds=$(if($durationIds -contains '10'){'10'}else{$durationIds[0]})}
$view=@{Rendering=$false;Styles=@()}

# ----- Left: Style (310px: the length, 10px, the 216px list), 12px, Prompt -----
$left=New-Object Windows.Forms.Panel -Property @{Dock='Fill'}
$right=New-Object Windows.Forms.Panel -Property @{Dock='Right';Width=400}
Add-NativeStack $shell.Body @($right,(New-NativeGap Right 16),$left)
$styleGroup=New-NativeGroup 'Style' Top 310
$durations=New-NativeSeg @($durationIds | ForEach-Object {@{Id=$_;Text=('{0}s ({1})' -f $_,@(Get-GrokStyles $_).Count)}})
$styleList=New-NativeCardList
$list=$styleList.List
Add-NativeStack $styleGroup @($durations,(New-NativeGap Top 10),$styleList.Frame)
$promptGroup=New-NativeGroup 'Prompt' Fill
$out=New-NativeOutput
Add-NativeStack $promptGroup @($out.Frame)
Add-NativeStack $left @($styleGroup,(New-NativeGap Top 12),$promptGroup)

# ----- Right: Thao tác, 12px, Video mẫu -----
$actionGroup=New-NativeGroup 'Thao tác' Top 188
$product=New-Object Windows.Forms.TextBox -Property @{Dock='Top';Height=72;Multiline=$true;AcceptsReturn=$true;ScrollBars='Vertical';Text=$state.product}
$copy=New-NativeButton 'Copy prompt' -Primary;$copy.Dock='Top'
Add-NativeStack $actionGroup @((New-NativeLabel 'Tên sản phẩm'),(New-NativeGap Top 4),$product,(New-NativeGap Top 8),$copy)
$videoGroup=New-NativeGroup 'Video mẫu' Fill
# Until a video is there: a dashed box saying why (still loading, offline, not uploaded).
$sample=New-Object ToolsHubNative.Box -Property @{Dock='Fill';Dashed=$true;VideoIcon=$true;Message='Đang tải video mẫu…'}
$videoBar=New-Object Windows.Forms.Panel -Property @{Dock='Bottom';Height=40;Visible=$false}
$play=New-NativeButton 'Phát';$play.Location=New-Object Drawing.Point(0,8);$play.Width=110
$videoBar.Controls.Add($play)
Add-NativeStack $videoGroup @($videoBar,$sample)
Add-NativeStack $right @($actionGroup,(New-NativeGap Top 12),$videoGroup)

# The video plays in Windows' own player (WPF MediaElement in the window): muted, looping, shown at its own shape from
# the top, like the page's <video>. Click it or Phát to play and pause.
$player=$null
try {
    Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase,WindowsFormsIntegration
    $media=New-Object System.Windows.Controls.MediaElement
    $media.LoadedBehavior='Manual';$media.UnloadedBehavior='Manual';$media.Stretch='Uniform';$media.IsMuted=$true;$media.ScrubbingEnabled=$true;$media.VerticalAlignment='Top'
    $canvas=New-Object System.Windows.Controls.Grid
    $canvas.Background=New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(240,240,240))
    [void]$canvas.Children.Add($media)
    $mediaHost=New-Object System.Windows.Forms.Integration.ElementHost -Property @{Dock='Fill';Visible=$false}
    $mediaHost.Child=$canvas
    $videoGroup.Controls.Add($mediaHost);$mediaHost.BringToFront()
    $player=@{Media=$media;Host=$mediaHost;Url='';Playing=$false}
} catch { $player=$null }
$videos=@{Loaded=$false;Failed=$false;Map=$null;Task=$null}
function Set-GrokPlaying([bool]$On) {
    if(-not $player -or -not $player.Url){return}
    if($On){$player.Media.Play()}else{$player.Media.Pause()}
    $player.Playing=$On;$play.Text=$(if($On){'Tạm dừng'}else{'Phát'})
}
function Update-GrokVideo {
    $video=$null
    if($videos.Loaded -and -not $videos.Failed -and $state.code -and $videos.Map){$video=$videos.Map.($state.code)}
    if($player -and $video -and $video.url){
        if($player.Url -ne [string]$video.url){
            $player.Url=[string]$video.url
            # Play then pause: the first frame shows, as preload="metadata" does on the page.
            $player.Media.Source=New-Object Uri([string]$video.url);$player.Media.Play();$player.Media.Pause();Set-GrokPlaying $false
        }
        $sample.Visible=$false;$player.Host.Visible=$true;$videoBar.Visible=$true
        return
    }
    if($player -and $player.Url){try{$player.Media.Stop()}catch{};$player.Media.Source=$null;$player.Url='';$player.Playing=$false}
    if($player){$player.Host.Visible=$false}
    $videoBar.Visible=$false;$sample.Visible=$true
    $sample.Message=if(-not $videos.Loaded){'Đang tải video mẫu…'}elseif($videos.Failed){'Chưa tải được video mẫu. Kiểm tra mạng rồi mở lại.'}elseif($video){'Máy này chưa phát được video mẫu.'}else{'Prompt này có video mẫu nhưng chưa được tải lên.'}
}
if($player){
    $player.Media.Add_MediaEnded({$player.Media.Position=[TimeSpan]::Zero;if($player.Playing){$player.Media.Play()}})
    $player.Media.Add_MediaFailed({$player.Url='';$player.Host.Visible=$false;$videoBar.Visible=$false;$sample.Visible=$true;$sample.Message='Không phát được video mẫu. Kiểm tra mạng rồi mở lại.'})
    $canvas.Add_MouseLeftButtonUp({Set-GrokPlaying (-not $player.Playing)})
}
$play.Add_Click({Set-GrokPlaying (-not $player.Playing)})

# ----- What the page's render() does -----
function Update-GrokPrompt {
    $style=@($view.Styles | Where-Object {$_.code -eq $state.code})[0]
    $name=$state.product.Trim()
    $text=if(-not $style){''}elseif($name){([string]$style.prompt).Replace([string]$prompts.placeholder,$name)}else{[string]$style.prompt}
    $out.Text.Text=$text -replace '\r?\n',"`r`n"
    $copy.Enabled=[bool]$style
}
function Update-Grok {
    Update-NativeSeg $durations $state.seconds
    $view.Styles=@(Get-GrokStyles $state.seconds)
    if(-not @($view.Styles | Where-Object {$_.code -eq $state.code}).Count){$state.code=$(if($view.Styles.Count){[string]$view.Styles[0].code}else{''})}
    $view.Rendering=$true
    try {
        $list.BeginUpdate();$list.Items.Clear()
        foreach($style in $view.Styles){[void]$list.Items.Add([string]$style.name)}
        $list.EndUpdate()
        for($i=0;$i -lt $view.Styles.Count;$i++){if($view.Styles[$i].code -eq $state.code){$list.SelectedIndex=$i}}
    } finally { $view.Rendering=$false }
    $list.Visible=[bool]$view.Styles.Count
    $styleList.Frame.Message=$(if($view.Styles.Count){''}else{"Chưa có prompt $($state.seconds)s."})
    Update-GrokPrompt;Update-GrokVideo
}
foreach($button in $durations.Controls){$button.Add_Click({param($sender) $state.seconds=[string]$sender.Tag;$state.code='';Update-Grok})}
$list.Add_SelectedIndexChanged({
    if($view.Rendering -or $list.SelectedIndex -lt 0){return}
    $state.code=[string]$view.Styles[$list.SelectedIndex].code;Update-GrokPrompt;Update-GrokVideo
})
$product.Add_TextChanged({$state.product=$product.Text;Update-GrokPrompt})
$copy.Add_Click({
    if(-not $state.product.Trim()){[void]$product.Focus();Show-NativeToast $form 'Điền tên sản phẩm';return}
    if($out.Text.Text){[Windows.Forms.Clipboard]::SetText($out.Text.Text);Show-NativeToast $form 'Đã copy prompt'}
})

# Sample videos: listed by the API from Drive (Tools Hub/Grok Video Prompt/Video mẫu/<n>s/<code>.mp4), fetched in the
# background so the window opens at once.
$client=New-Object Net.WebClient
$client.Encoding=[Text.Encoding]::UTF8
$videoTimer=New-Object Windows.Forms.Timer -Property @{Interval=250}
$videoTimer.Add_Tick({
    if(-not $videos.Task -or -not $videos.Task.IsCompleted){return}
    $videoTimer.Stop();$videos.Loaded=$true
    try{$videos.Map=($videos.Task.GetAwaiter().GetResult() | ConvertFrom-Json).videos;if(-not $videos.Map){$videos.Map=New-Object psobject}}catch{$videos.Failed=$true}
    Update-GrokVideo
})
$form.Add_Shown({$videos.Task=$client.DownloadStringTaskAsync([Uri]'https://tools-hub-api.hoangpham2263.workers.dev/grok/videos');$videoTimer.Start()})
$form.Add_FormClosed({
    Write-NativeState $statePath $state
    $videoTimer.Stop();$videoTimer.Dispose();$client.Dispose()
    if($player){try{$player.Media.Stop();$player.Media.Source=$null}catch{};$player.Host.Dispose()}
})
Update-Grok
# Opened from the menu (hub/launch.ps1) the window is a page of the menu's window, which runs it.
if(-not $BuildOnly -and -not $global:ToolsHubHosted){Show-NativeToolWindow $shell $PSCommandPath}
