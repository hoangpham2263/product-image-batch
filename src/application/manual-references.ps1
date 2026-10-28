function Read-ManualReferenceMap([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)){return [pscustomobject]@{schema_version=1;allow_library_fallback=$false;preferred_source_group='Áo';entries=@()}}
    $map=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    if($map.schema_version -ne 1){throw 'Invalid manual reference map.'}
    if(-not $map.PSObject.Properties['preferred_source_group']){$map|Add-Member NoteProperty preferred_source_group 'Áo'}
    $map.preferred_source_group=Resolve-SourcePhotoGroup $map.preferred_source_group
    $seen=@{}
    foreach($entry in @($map.entries)){
        $uri=$null
        if(-not [Uri]::TryCreate($entry.product_url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or (-not $entry.file -and -not $entry.product_file) -or ($entry.file -and $entry.sha256 -notmatch '^[a-f0-9]{64}$') -or ($entry.product_file -and $entry.product_sha256 -notmatch '^[a-f0-9]{64}$') -or $seen.ContainsKey($entry.product_url)){throw 'Invalid or duplicate manual reference entry.'}
        $seen[$entry.product_url]=$true
    }
    return $map
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
    $fileKey=if($Role -eq 'Product'){'product_file'}else{'file'}
    $hashKey=if($Role -eq 'Product'){'product_sha256'}else{'sha256'}
    $entry|Add-Member NoteProperty $fileKey $dest -Force
    $entry|Add-Member NoteProperty $hashKey (Get-BytesHash ([IO.File]::ReadAllBytes($dest))) -Force
    $entry|Add-Member NoteProperty origin 'user_reference' -Force
    $map.entries=@($map.entries|Where-Object product_url -ne $Url)+@($entry)
    Write-FeedbackJson $mapPath $map
    return $mapPath
}
