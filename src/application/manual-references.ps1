function Read-ManualReferenceMap([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)){return [pscustomobject]@{schema_version=1;allow_library_fallback=$false;preferred_source_group='Áo';entries=@()}}
    $map=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    if($map.schema_version -ne 1){throw 'Invalid manual reference map.'}
    if(-not $map.PSObject.Properties['preferred_source_group']){$map|Add-Member NoteProperty preferred_source_group 'Áo'}
    $map.preferred_source_group=Resolve-SourcePhotoGroup $map.preferred_source_group
    $seen=@{}
    foreach($entry in @($map.entries)){
        # A link can carry several scene images; each one becomes its own generated image.
        # file/sha256 mirror the first scene so older maps and readers keep working.
        $scenes=@(Get-ManualScenes $entry)
        $entry|Add-Member NoteProperty scenes $scenes -Force
        $uri=$null
        if(-not [Uri]::TryCreate($entry.product_url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or (-not $scenes.Count -and -not $entry.product_file) -or @($scenes|Where-Object{-not $_.file -or $_.sha256 -notmatch '^[a-f0-9]{64}$'}).Count -or ($entry.product_file -and $entry.product_sha256 -notmatch '^[a-f0-9]{64}$') -or $seen.ContainsKey($entry.product_url)){throw 'Invalid or duplicate manual reference entry.'}
        $seen[$entry.product_url]=$true
    }
    return $map
}

function Get-ManualScenes($Entry) {
    if(-not $Entry){return @()}
    if($Entry.PSObject.Properties['scenes'] -and @($Entry.scenes).Count){return @($Entry.scenes|ForEach-Object{[pscustomobject]@{file=$_.file;sha256=$_.sha256}})}
    if($Entry.file){return @([pscustomobject]@{file=$Entry.file;sha256=$Entry.sha256})}
    return @()
}

function Set-ManualScenes($Entry,$Scenes) {
    $Scenes=@($Scenes)
    $Entry|Add-Member NoteProperty scenes $Scenes -Force
    if($Scenes.Count){$Entry|Add-Member NoteProperty file $Scenes[0].file -Force;$Entry|Add-Member NoteProperty sha256 $Scenes[0].sha256 -Force}
    else{foreach($name in 'file','sha256','scenes'){$Entry.PSObject.Properties.Remove($name)}}
}

# Removes one scene image (0-based) from a link; the link entry is dropped when nothing is left.
function Remove-ManualScene([string]$MapPath,[string]$Url,[int]$Index) {
    $map=Read-ManualReferenceMap $MapPath
    foreach($entry in @($map.entries|Where-Object product_url -eq $Url)){
        $scenes=[Collections.Generic.List[object]]::new();foreach($scene in @(Get-ManualScenes $entry)){$scenes.Add($scene)}
        if($Index -ge 0 -and $Index -lt $scenes.Count){$scenes.RemoveAt($Index)}
        Set-ManualScenes $entry $scenes.ToArray()
    }
    $map.entries=@($map.entries|Where-Object{@(Get-ManualScenes $_).Count -or $_.product_file})
    New-Item -ItemType Directory -Path (Split-Path $MapPath -Parent) -Force|Out-Null
    Write-FeedbackJson $MapPath $map
}

function Save-ManualReference([string]$ProjectRoot,[string]$Url,[string]$ImagePath,[ValidateSet('Scene','Product')][string]$Role='Scene') {
    $uri=$null
    if(-not [Uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https')){throw 'Invalid product URL.'}
    $extension=[IO.Path]::GetExtension($ImagePath).ToLowerInvariant()
    if($extension -notin @('.png','.jpg','.jpeg')){throw 'Choose a PNG or JPEG reference.'}
    $folder=Join-Path $ProjectRoot 'workspace/reference-inputs'
    New-Item -ItemType Directory -Path $folder -Force|Out-Null
    $mapPath=Join-Path $folder 'references.json'
    $map=Read-ManualReferenceMap $mapPath
    $dest=Join-Path $folder ([Guid]::NewGuid().ToString('N')+$extension)
    Copy-Item -LiteralPath $ImagePath -Destination $dest
    $existing=@($map.entries|Where-Object product_url -eq $Url)
    $entry=if($existing.Count){$existing[0]}else{[pscustomobject]@{product_url=$Url}}
    $hash=Get-BytesHash ([IO.File]::ReadAllBytes($dest))
    if($Role -eq 'Product'){
        $entry|Add-Member NoteProperty product_file $dest -Force
        $entry|Add-Member NoteProperty product_sha256 $hash -Force
    }else{
        # Scene images are added, not replaced; the same picture twice is kept once.
        $scenes=@(Get-ManualScenes $entry)
        if(@($scenes|Where-Object sha256 -eq $hash).Count){Remove-Item -LiteralPath $dest -Force}
        else{Set-ManualScenes $entry (@($scenes)+@([pscustomobject]@{file=$dest;sha256=$hash}))}
    }
    $entry|Add-Member NoteProperty origin 'user_reference' -Force
    $map.entries=@($map.entries|Where-Object product_url -ne $Url)+@($entry)
    Write-FeedbackJson $mapPath $map
    return $mapPath
}
