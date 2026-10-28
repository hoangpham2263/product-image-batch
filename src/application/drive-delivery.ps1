# Keep finished images/review text until every scene of a URL is delivered.
function Get-DeliveryKey($Item) {
    $parts=@($Item.Url)
    if($Item.PSObject.Properties['ApprovedImageHash']){return Get-BytesHash ([Text.Encoding]::UTF8.GetBytes(($parts+@('approved',$Item.ApprovedImageHash) -join "`n")))}
    $entry=@($script:Config.ManualReferences.entries|Where-Object product_url -eq $Item.Url)
    if($entry.Count -and $entry[0].product_file){
        if(-not (Test-Path -LiteralPath $entry[0].product_file) -or (Get-BytesHash ([IO.File]::ReadAllBytes($entry[0].product_file))) -ne $entry[0].product_sha256){throw '[CAUSE:PRODUCT_INPUT] Attached product changed.'}
        $parts+=@($entry[0].product_sha256)
    }
    $scene=if($Item.PSObject.Properties['Scene']){$Item.Scene}elseif($entry.Count){@(Get-ManualScenes $entry[0])|Select-Object -First 1}
    if($scene){
        if(-not (Test-Path -LiteralPath $scene.file) -or (Get-BytesHash ([IO.File]::ReadAllBytes($scene.file))) -ne $scene.sha256){throw '[CAUSE:PRODUCT_INPUT] Attached scene changed.'}
        $parts+=@($scene.sha256)
    }
    if($script:Config.Feedback){$parts+=@($script:Config.Feedback.Record.id,$script:Config.Feedback.Record.requested_change)}
    return Get-BytesHash ([Text.Encoding]::UTF8.GetBytes(($parts -join "`n")))
}

function Read-DeliveryCache($Item) {
    if(-not $script:Config.DeliveryRoot -or (-not $script:Config.Drive -and -not $script:Config.DriveRequired)){return}
    $key=Get-DeliveryKey $Item
    $path=Join-Path $script:Config.DeliveryRoot "$key.json"
    if(-not (Test-Path -LiteralPath $path)){return}
    $saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    if($saved.schema_version -ne 1 -or $saved.product_url -ne $Item.Url -or $saved.key -ne $key){throw '[CAUSE:DRIVE_UPLOAD] Invalid saved delivery.'}
    if(-not (Test-Path -LiteralPath $saved.row.photo_path) -or (Get-BytesHash ([IO.File]::ReadAllBytes($saved.row.photo_path))) -ne $saved.image_sha256){throw '[CAUSE:DRIVE_UPLOAD] Saved image changed; delivery stopped.'}
    return $saved
}

function Restore-DeliveryCache($Saved,[string]$ItemId) {
    $manifestPath=Join-Path $Saved.refs_folder 'manifest.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($manifest.product_url -ne $Saved.product_url){throw '[CAUSE:DRIVE_UPLOAD] Saved input URL mismatch.'}
    $folder=Join-Path $script:Batch.Refs $ItemId
    New-Item -ItemType Directory -Path $folder -Force|Out-Null
    foreach($entry in $manifest.images){
        $source=Resolve-FeedbackChild $Saved.refs_folder $entry.file
        if((Get-BytesHash ([IO.File]::ReadAllBytes($source))) -ne $entry.sha256){throw '[CAUSE:DRIVE_UPLOAD] Saved inputs changed.'}
        $destination=Resolve-FeedbackChild $folder $entry.file
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force|Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
    $image=Join-Path $script:Batch.Images "$ItemId.png"
    Copy-Item -LiteralPath $Saved.row.photo_path -Destination $image
    $manifest.item_id=$ItemId;$manifest.output="../../images/$ItemId.png"
    Write-FeedbackJson (Join-Path $folder 'manifest.json') $manifest
    $Saved.row.photo_path=$image -replace '\\','/'
    return $Saved.row
}

function Save-DeliveryCache($Item,[string]$ItemId,$Row) {
    if(-not $script:Config.DeliveryRoot -or (-not $script:Config.Drive -and -not $script:Config.DriveRequired)){return}
    $key=Get-DeliveryKey $Item
    $Row|Add-Member NoteProperty delivery_key $key -Force
    New-Item -ItemType Directory -Path $script:Config.DeliveryRoot -Force|Out-Null
    Write-FeedbackJson (Join-Path $script:Config.DeliveryRoot "$key.json") ([ordered]@{
        schema_version=1;key=$key;product_url=$Item.Url;row=$Row
        image_sha256=Get-BytesHash ([IO.File]::ReadAllBytes($Row.photo_path))
        refs_folder=Join-Path $script:Batch.Refs $ItemId
    })
}

function Assert-PublicPhotoDelivery($Row) {
    if(-not $script:Config.Drive -and -not $script:Config.DriveRequired){return}
    $uri=$null
    if(-not [Uri]::TryCreate([string]$Row.photo_url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or -not $uri.Host){throw '[CAUSE:DRIVE_UPLOAD] Image has no public HTTPS link; CSV not exported.'}
}

# Called by each image worker right after generation, and again by the coordinator for retries.
function Complete-DriveDelivery($Row,[int]$Index=0) {
    if(-not $script:Config.Drive){
        if($script:Config.DriveRequired){throw '[CAUSE:DRIVE_CONFIG] Log in to Google Drive before creating images.'}
        return $Row
    }
    if($Row.photo_url -notmatch '^https://'){
        $previousIndex=$script:DriveUploadIndex;$script:DriveUploadIndex=$Index
        try{$Row.photo_url=Publish-ImageToDrive $Row.photo_path $script:Batch.Id $Row.product_handle}
        finally{$script:DriveUploadIndex=$previousIndex}
        Write-Host "  [DRIVE] $($Row.photo_url)" -ForegroundColor Cyan
    }
    Assert-PublicPhotoDelivery $Row
    if($Row.delivery_key -and $script:Config.DeliveryRoot){
        $path=Join-Path $script:Config.DeliveryRoot "$($Row.delivery_key).json"
        $saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
        $saved.row=$Row;Write-FeedbackJson $path $saved
    }
    return $Row
}

function Remove-CompletedDeliveryCache([string]$Url,[string]$Key='') {
    if(-not $script:Config.DeliveryRoot -or -not (Test-Path -LiteralPath $script:Config.DeliveryRoot)){return}
    foreach($file in @(Get-ChildItem -LiteralPath $script:Config.DeliveryRoot -File -Filter '*.json')){
        $saved=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json
        if($saved.product_url -eq $Url -and (-not $Key -or $saved.key -eq $Key)){Remove-Item -LiteralPath $file.FullName}
    }
}
