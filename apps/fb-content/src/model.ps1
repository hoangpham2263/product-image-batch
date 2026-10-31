# Same draft composition rules as ui/index.html. AI generation is not implemented on either platform.
$script:SocialPlatforms=@(
    @{id='facebook';name='Facebook';limit=63206;tags=5;tip='Link bấm được ngay trong bài · ảnh 4:5 hoặc 1:1'},
    @{id='instagram';name='Instagram';limit=2200;tags=30;tip='Link trong caption không bấm được: để ở bio · ảnh 4:5'},
    @{id='threads';name='Threads';limit=500;tags=1;tip='Tối đa 500 ký tự, một chủ đề (#) · ảnh 4:5'},
    @{id='tiktok';name='TikTok';limit=4000;tags=5;tip='Caption ngắn đi kèm video · ảnh/video 9:16'}
)
function Get-SocialPost($Row,[string]$Platform,[string]$Tone) {
    $settings=@($script:SocialPlatforms | Where-Object id -eq $Platform)[0]
    $name=([string]$Row.name).Trim();if(-not $name){$name='[Tên sản phẩm]'}
    $points=@(([string]$Row.points -split '\r?\n') | ForEach-Object {$_.Trim()} | Where-Object {$_})
    $link=([string]$Row.link).Trim();$brand=([string]$Row.brand).Trim()
    $tags=@(([string]$Row.tags -split '\s+') | Where-Object {$_} | ForEach-Object {if($_.StartsWith('#')){$_}else{'#'+$_}} | Select-Object -First $settings.tags)
    $parts=New-Object Collections.Generic.List[string]
    $opening=switch($Tone){'short'{"$name."};'sale'{"Giới thiệu $name."};default{"Có những món đồ mình chọn vì đẹp, và có những món ở lại lâu vì hợp với nhịp sống trong nhà. $name là một món như vậy."}}
    $parts.Add($opening)
    if($Platform -in @('threads','tiktok')){
        if($points.Count){$parts.Add((($points | Select-Object -First 3) -join ' · ')+$(if($Platform -eq 'tiktok'){'.'}else{''}))}
        if($Platform -eq 'threads' -and $link){$parts.Add($link)}
        if($Platform -eq 'tiktok'){$parts.Add($(if($brand){"Xem ở $brand, link trong bio."}else{'Link trong bio.'}))}
    }else{
        if($points.Count){$parts.Add((@($points | ForEach-Object {$(if($Platform -eq 'instagram'){'✓ '}else{'- '})+$_}) -join "`n"))}
        if($brand){$parts.Add("$brand — "+$(if($Tone -eq 'story'){'vẻ đẹp tự nhiên, qua đôi tay người thợ.'}elseif($Platform -eq 'instagram'){'link ở bio.'}else{'xem thêm tại link bên dưới.'}))}
        elseif($Platform -eq 'instagram' -and $link){$parts.Add('Link ở bio.')}
        if($Platform -eq 'facebook' -and $link){$parts.Add($link)}
    }
    if($tags.Count){$parts.Add(($tags -join ' '))}
    return $parts -join $(if($Platform -eq 'tiktok'){' '}else{"`n`n"})
}
