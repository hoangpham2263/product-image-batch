function Read-ManualReferenceMap([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)){return [pscustomobject]@{schema_version=1;allow_library_fallback=$false;entries=@()}}
    $map=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    if($map.schema_version -ne 1){throw 'Invalid manual reference map.'}
    $seen=@{}
    foreach($entry in @($map.entries)){
        $uri=$null
        if(-not [Uri]::TryCreate($entry.product_url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or -not $entry.file -or $entry.sha256 -notmatch '^[a-f0-9]{64}$' -or $seen.ContainsKey($entry.product_url)){throw 'Invalid or duplicate manual reference entry.'}
        $seen[$entry.product_url]=$true
    }
    return $map
}

function Save-ManualReference([string]$ProjectRoot,[string]$Url,[string]$ImagePath) {
    $uri=$null
    if(-not [Uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https')){throw 'Invalid product URL.'}
    $extension=[IO.Path]::GetExtension($ImagePath).ToLowerInvariant()
    if($extension -notin @('.png','.jpg','.jpeg')){throw 'Choose a PNG or JPEG reference.'}
    $image=[Drawing.Image]::FromFile($ImagePath)
    try{if($image.Width -lt 32 -or $image.Height -lt 32){throw 'Reference image is too small.'}}finally{$image.Dispose()}
    $folder=Join-Path $ProjectRoot 'workspace/reference-inputs'
    New-Item -ItemType Directory -Path $folder -Force|Out-Null
    $mapPath=Join-Path $folder 'references.json'
    $map=Read-ManualReferenceMap $mapPath
    $dest=Join-Path $folder ([Guid]::NewGuid().ToString('N')+$extension)
    Copy-Item -LiteralPath $ImagePath -Destination $dest
    $entry=[pscustomobject]@{product_url=$Url;file=$dest;sha256=Get-BytesHash ([IO.File]::ReadAllBytes($dest));origin='user_reference'}
    $map.entries=@($map.entries|Where-Object product_url -ne $Url)+@($entry)
    Write-FeedbackJson $mapPath $map
    return $mapPath
}
