# Deliver the first technically valid result. Visual review belongs to the user.
function Complete-ProductImage($Request, $Context, [string]$ItemId) {
    $output = $Request.Output
    if ($Context.presentation -and $Context.presentation -ne 'worn' -and -not $Request.SceneBase) { throw 'Image technical validation failed: original room is missing for a localized object edit.' }
    Write-Host '  [IMAGE] Creating one complete scene...' -ForegroundColor Cyan
    $interruption = ''
    $maxAttempts=3
    if($script:Config -and $script:Config.ContainsKey('ImageSubmissionAttempts')){$maxAttempts=[Math]::Max(1,[Math]::Min(5,[int]$script:Config.ImageSubmissionAttempts))}
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Host "  [IMAGE-ATTEMPT] $attempt/$maxAttempts" -ForegroundColor Cyan
        try{$reply = Invoke-ImageGeneration $Request $ItemId $attempt $interruption}
        catch{
            if($_.Exception.Message -notmatch '\[CAUSE:(AI_TIMEOUT|NETWORK|BUSY)\]' -or $attempt -eq $maxAttempts){throw}
            $cause=$Matches[1]
            # Keep partial evidence before the next attempt clears output and mask.
            foreach($part in @(@($Request.Output,'generated'),@($Request.EditMask,'mask'))){
                if($part[0] -and (Test-Path -LiteralPath $part[0])){Copy-Item -LiteralPath $part[0] -Destination (Join-Path $script:Batch.Logs "$ItemId-attempt-$attempt-$($part[1]).png") -Force}
            }
            if(-not $interruption){$interruption="Previous generation interrupted ($cause); no complete image files were delivered."}
            Write-Host "  [IMAGE-RETRY] $cause $($attempt+1)/$maxAttempts" -ForegroundColor Yellow
            $delay=3;if($script:Config.ContainsKey('AiRetryDelaySeconds')){$delay=[Math]::Max(0,[int]$script:Config.AiRetryDelaySeconds)}
            if($delay){Start-Sleep -Seconds $delay}
            continue
        }
        # This only checks file/mask dimensions, opacity and restoration rules in code.
        # Never request an AI verdict or automatically improve a delivered image.
        Merge-ProductIntoScene $Request $ItemId $attempt
        $status=[ordered]@{status='awaiting_user_review';ai_image_qa_performed=$false;generation_attempt=$attempt;output=$output}
        [IO.File]::WriteAllText((Join-Path $script:Batch.Logs "$ItemId-review-status.json"),($status|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        Write-Host '  [AWAITING-REVIEW] Image ready for user review; no automatic visual QA or repair.' -ForegroundColor Cyan
        return $reply
    }
}
