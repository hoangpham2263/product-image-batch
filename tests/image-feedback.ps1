. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
. (Join-Path $root 'src/ui/image-feedback.ps1')
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('feedback-'+[Guid]::NewGuid().ToString('N'))
try {
    $batch=Join-Path $temp 'workspace/output/original'
    $refs=Join-Path $batch 'refs/001-table'
    $images=Join-Path $batch 'images'
    New-Item -ItemType Directory -Path $refs,$images -Force|Out-Null
    foreach($path in @((Join-Path $refs '01-scene.png'),(Join-Path $refs '02-product.png'),(Join-Path $images '001-table.png'))){
        $bitmap=[Drawing.Bitmap]::new(8,6);try{$graphics=[Drawing.Graphics]::FromImage($bitmap);$graphics.Clear([Drawing.Color]::White);$graphics.Dispose();$bitmap.SetPixel(1,1,[Drawing.Color]::Red);$bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    }
    $context=[pscustomobject]@{product='Table and matching wooden chairs';presentation='placed';details='slab legs and curved wooden chair backs';setting='dining room';reject='upholstered replacement chairs';source_categories=@('dining-tables');branding='none'}
    $manifest=[pscustomobject]@{schema_version=1;item_id='001-table';product=$context.product;product_url='https://example.test/p/table';product_context=$context;images=@()}
    foreach($pair in @(@('01-scene.png','scene'),@('02-product.png','product'))){$manifest.images+=@([pscustomobject]@{file=$pair[0];role=$pair[1];category='dining-tables';sha256=Get-BytesHash ([IO.File]::ReadAllBytes((Join-Path $refs $pair[0])))})}
    Write-FeedbackJson (Join-Path $refs 'manifest.json') $manifest
    $photo=Join-Path $images '001-table.png'
    [IO.File]::WriteAllText((Join-Path $temp 'AGENTS.md'),"# Existing project rules`r`nPreserve this manual instruction.`r`n",[Text.UTF8Encoding]::new($true))
    $change='Replace ALL old upholstered chairs with the matching curved wooden chairs; preserve slab legs.'
    $path=Save-ImageFeedback $temp $photo $change product $true
    $feedback=Read-ImageFeedback $path
    Assert ($feedback.Record.status -eq 'saved' -and $feedback.Record.requested_change -eq $change) 'Human correction was not saved.'
    Assert (Test-Path -LiteralPath $feedback.RejectedImage) 'Rejected image snapshot missing.'
    $script:Config=@{FeedbackRoot=(Join-Path $temp 'workspace/feedback')}
    Assert ((Get-ImageFeedbackGuidance $context $manifest.product_url) -match 'Replace ALL') 'Saved lesson never reaches future prompts.'
    Assert ((Get-Content (Join-Path $temp 'AGENTS.md') -Raw -Encoding UTF8) -match 'Replace ALL') 'Saved user lesson was not written to AGENTS.md.'
    $agentPath=Join-Path $temp 'AGENTS.md';$agentText=[IO.File]::ReadAllText($agentPath)
    Assert ($agentText.StartsWith('# Existing project rules')) 'Saving a lesson overwrote unrelated project instructions.'
    [IO.File]::WriteAllText($agentPath,$agentText.Replace('Replace ALL','Central edit: replace all'),[Text.UTF8Encoding]::new($true))
    Assert ((Get-ImageFeedbackGuidance $context $manifest.product_url) -match 'Central edit: replace all') 'Editing AGENTS.md did not update the runtime lesson.'
    [IO.File]::WriteAllText($agentPath,$agentText,[Text.UTF8Encoding]::new($true))
    $history=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    $history.requested_change='History text is not the lesson source';Write-FeedbackJson $path $history
    Assert ((Get-ImageFeedbackGuidance $context $manifest.product_url) -match 'Replace ALL') 'Generation still reads private history instead of AGENTS.md.'
    $history.requested_change=$change;Write-FeedbackJson $path $history
    Assert ((Get-ImageFeedbackGuidance $context $manifest.product_url) -match 'COLOR CORRECTION CONTRACT' -and (Get-ImageFeedbackGuidance $context $manifest.product_url) -match 'does NOT by itself request a different wood species') 'Color feedback must not silently authorize restaining the source product.'
    Assert (-not (Get-ImageFeedbackGuidance $context 'https://example.test/p/other')) 'Product-only lesson leaked to another product.'
    $categoryPath=Save-ImageFeedback $temp $photo 'Check every chair component against the source.' category $true
    Assert ((Get-ImageFeedbackGuidance $context 'https://example.test/p/other') -match 'every chair') 'Explicit category lesson did not reach matching products.'
    $other=[pscustomobject]@{source_categories=@('polo-shirts')}
    Assert (-not (Get-ImageFeedbackGuidance $other 'https://example.test/p/other')) 'Category lesson leaked into another category.'
    Set-ImageFeedbackRemember $temp $categoryPath $false
    Assert (-not (Get-ImageFeedbackGuidance $context 'https://example.test/p/other')) 'Disabled lesson is still active.'
    $disabledId=(Get-Content -LiteralPath $categoryPath -Raw -Encoding UTF8|ConvertFrom-Json).id
    Assert (-not @(Read-AgentLessons (Join-Path $temp 'AGENTS.md')|Where-Object id -eq $disabledId).Count) 'Disabled lesson remains in the central instructions.'
    $bad=$false;try{Resolve-FeedbackChild $refs '../outside.png'|Out-Null}catch{$bad=$true};Assert $bad 'Reference traversal was accepted.'
    $bad=$false;try{Set-ImageFeedbackStatus $path accepted}catch{$bad=$true};Assert $bad 'Accepted feedback before a new result existed.'
    # A correction reuses the saved inputs, even when the original source later changes.
    [IO.File]::WriteAllText((Join-Path $refs '01-scene.png'),'changed original')
    $feedback=Read-ImageFeedback $path
    $script:Config=@{Feedback=$feedback;FeedbackRoot=(Join-Path $temp 'workspace/feedback');SourceDir=$temp;StyleExample='';WritingStyle=[pscustomobject]@{scene_rules=@()}}
    $script:Batch=New-Batch (Join-Path $temp 'revisions')
    function Read-ProductInput {throw 'Correction must not download new product inputs.'}
    function Select-ProductReferences {throw 'Correction must not randomly choose a different room.'}
    function Resolve-ProductContext {throw 'Correction with saved context must not reclassify the product.'}
    function Complete-ProductImage($Request,$Context,$ItemId){
        Assert ($Request.Prompt -match 'Replace ALL' -and $Request.Prompt -match 'REJECTED RESULT') 'Current correction or rejected-image role missing from generation.'
        Assert ($Request.Images.Count -eq 3 -and $Request.SceneBase -eq $Request.Images[0]) 'Original scene, actual product and rejected output roles changed.'
        Copy-Item -LiteralPath $Request.Images[2] -Destination $Request.Output
        return 'BRAND: none'
    }
    function New-Review {return 'Visible wood grain and curved chair backs.'}
    $result=Invoke-ProductItem ([pscustomobject]@{Url=$manifest.product_url;Handle='table'}) '001-table' ([Collections.ArrayList]::new())
    Assert ((Test-Path -LiteralPath $result.photo_path) -and (Test-Path -LiteralPath $photo)) 'Revision overwrote the original or did not create a new output.'
    $saved=Get-Content -LiteralPath (Join-Path $script:Batch.Refs '001-table/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($saved.feedback_id -eq $feedback.Record.id -and @($saved.images|Where-Object role -eq rejected_result).Count -eq 1) 'Revision provenance or follow-up link missing.'
    Assert (-not (Get-Command Test-ProductScene -ErrorAction SilentlyContinue)) 'Automatic visual QA must not be loaded into the workflow.'
    Set-ImageFeedbackStatus $path running
    Set-ImageFeedbackStatus $path awaiting_review $script:Batch.Dir
    Set-ImageFeedbackStatus $path accepted
    Assert ((Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json).status -eq 'accepted') 'User acceptance did not persist.'
    # Exercise the actual background runspace boundary with serialized feedback.
    $mockModule=Join-Path $temp 'feedback-worker-fixture.ps1'
    $definitions=@('Assert','Read-ProductInput','Select-ProductReferences','Resolve-ProductContext','Complete-ProductImage','New-Review')|ForEach-Object{"function $_ {"+(Get-Item "Function:\$_").Definition+"}`r`n"}
    [IO.File]::WriteAllText($mockModule,($definitions -join "`r`n"),[Text.UTF8Encoding]::new($true))
    New-Item -ItemType Directory -Path (Join-Path $temp 'data') -Force|Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'data/names.txt') -Destination (Join-Path $temp 'data/names.txt')
    $mainQueue=Join-Path $temp 'workspace/urls.txt';[IO.File]::WriteAllText($mainQueue,'https://example.test/p/untouched')
    $retryQueue=Join-Path $feedback.Folder 'retry-urls.txt';[IO.File]::WriteAllText($retryQueue,$manifest.product_url)
    Invoke-BatchWorkflow $temp $retryQueue (Join-Path $temp 'worker-revisions') 1 (@($script:WorkflowModuleFiles)+@($mockModule))
    Assert ((Get-Content -LiteralPath $mainQueue -Raw) -eq 'https://example.test/p/untouched') 'A revision modified the normal product queue.'
    $exported=@(Import-BatchRows $script:Batch.Dir)
    Assert ($exported.Count -eq 1 -and (Test-Path -LiteralPath $exported[0].photo_url)) 'Background correction did not export its new result.'
    # A human can hand over a visibly accepted image independently of an AI verdict.
    $acceptedSource=$exported[0].photo_url
    $acceptedHash=Get-BytesHash ([IO.File]::ReadAllBytes($acceptedSource))
    function Test-ProductScene {throw 'Human-approved export must not ask AI to override the user verdict.'}
    function Invoke-ImageGeneration {throw 'Human-approved export must not regenerate the accepted image.'}
    $delivered=Export-ApprovedProduct $temp $acceptedSource (Join-Path $temp 'approved-deliveries')
    $deliveryRows=@(Import-BatchRows $delivered)
    $proof=Get-Content -LiteralPath (Join-Path $delivered 'user-approval.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($deliveryRows.Count -eq 1 -and $deliveryRows[0].verified_purchase -eq 'false') 'Approved export did not provide a CSV or invented a verified purchase.'
    Assert ($proof.completion_method -eq 'explicit_user_approval' -and -not $proof.ai_image_qa_passed) 'Human approval was misrepresented as an AI QA pass.'
    Assert ((Get-BytesHash ([IO.File]::ReadAllBytes($acceptedSource))) -eq $acceptedHash) 'Human-approved export changed its original input.'
    Assert ((Get-Content -LiteralPath (Join-Path $delivered 'urls.completed.txt') -Raw).Trim() -eq $manifest.product_url) 'Approved handover did not checkpoint completion.'
    function New-Review {throw 'fixture text service unavailable'}
    $textFailureDelivery=Export-ApprovedProduct $temp $acceptedSource (Join-Path $temp 'approved-deliveries')
    $textFailureRows=@(Import-BatchRows $textFailureDelivery)
    Assert ($textFailureRows.Count -eq 1 -and -not $textFailureRows[0].body -and (Test-Path -LiteralPath $textFailureRows[0].photo_url)) 'Optional text failure prevented delivery of the approved image.'
    # Build the actual WinForms dialog without showing it or invoking paid AI calls.
    $view=New-ImageFeedbackDialog $temp (Join-Path $temp 'worker-revisions')
    try {
        Assert ($null -ne $view.State.Target) 'GUI could not load an archived revision for comparison.'
        Assert ($view.Form.Controls.Find('RequestedChange',$true)[0].MaxLength -eq 4000) 'Correction field missing or unbounded.'
        Assert ($view.Form.Controls.Find('RememberLesson',$true)[0].Checked) 'Lesson default was not enabled.'
        Assert ($view.Form.Controls.Find('LessonScope',$true)[0].SelectedIndex -eq 0) 'GUI default must keep lessons product-specific.'
        $view.Form.ShowInTaskbar=$false;$view.Form.StartPosition='Manual';$view.Form.Location=[Drawing.Point]::new(-32000,-32000)
        $view.Form.Show();$view.Form.Refresh()
        $screen=[Drawing.Bitmap]::new($view.Form.Width,$view.Form.Height)
        try{$view.Form.DrawToBitmap($screen,[Drawing.Rectangle]::new(0,0,$screen.Width,$screen.Height));$screen.Save((Join-Path $TestWorkspaceRoot 'feedback-dialog-preview.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$screen.Dispose()}
        $view.Form.Controls.Find('RequestedChange',$true)[0].Text='The chair backs are still wrong. Use the curved original backs.'
        $view.Form.Controls.Find('RememberLesson',$true)[0].Checked=$false
        $view.Form.Controls.Find('RetryImage',$true)[0].PerformClick()
        Assert (Test-Path -LiteralPath $view.State.FeedbackPath) 'Actual GUI retry click did not save a feedback request.'
        $follow=Read-ImageFeedback $view.State.FeedbackPath
        Assert ($follow.Record.parent_feedback_id -eq $feedback.Record.id -and -not $follow.Record.remember) 'Follow-up link or user lesson preference was lost.'
    } finally {
        foreach($name in @('ProductPreview','ResultPreview')){Set-FeedbackPreview $view.Form.Controls.Find($name,$true)[0] ''}
        $view.Form.Dispose()
    }
    Set-ImageFeedbackStatus $path failed $script:Batch.Dir 'fixture failure'
    $failed=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($failed.status -eq 'failed' -and $failed.error -eq 'fixture failure') 'Failure status did not preserve the diagnostic for follow-up.'
    # Approved handover also retries only Drive, retaining its image and text.
    $previousDrive=$script:Config.Drive;$previousRequired=$script:Config.DriveRequired;$previousRoot=$script:Config.DeliveryRoot
    try{
        $script:Config.Drive=@{ApiUrl='https://api.test';AdminKey='test'};$script:Config.DriveRequired=$true;$script:Config.DeliveryRoot=Join-Path $temp 'approved-pending'
        function New-Review {return 'Approved review retained for upload retry.'}
        function Publish-ImageToDrive {throw '[CAUSE:DRIVE_UPLOAD] fixture upload failure'}
        $uploadFailed=$false
        try{Export-ApprovedProduct $temp $acceptedSource (Join-Path $temp 'approved-online')|Out-Null}catch{$uploadFailed=$_.Exception.Message -match 'DRIVE_UPLOAD'}
        Assert $uploadFailed 'Approved upload error was swallowed.'
        function New-Review {throw 'Approved upload retry must reuse saved text.'}
        function Publish-ImageToDrive {return 'https://api.test/img/approved.png'}
        $online=Export-ApprovedProduct $temp $acceptedSource (Join-Path $temp 'approved-online')
        $onlineRows=@(Import-BatchRows $online)
        Assert ($onlineRows.Count -eq 1 -and $onlineRows[0].body -eq 'Approved review retained for upload retry.' -and $onlineRows[0].photo_url -eq 'https://api.test/img/approved.png') 'Approved retry regenerated text or exported a local image path.'
        Assert (@(Get-ChildItem $script:Config.DeliveryRoot -Filter '*.json').Count -eq 0) 'Completed approval retained a pending upload.'
    }finally{$script:Config.Drive=$previousDrive;$script:Config.DriveRequired=$previousRequired;$script:Config.DeliveryRoot=$previousRoot}
    # Snapshot corruption is rejected rather than silently using modified references.
    [IO.File]::WriteAllText((Join-Path $feedback.Folder 'refs/01-scene.png'),'tampered snapshot')
    $bad=$false;try{Read-ImageFeedback $path|Out-Null}catch{$bad=$true};Assert $bad 'Tampered feedback input was accepted.'
    Write-Host 'PASS: saved feedback, scoped lessons, immutable retry inputs, generation wiring without visual QA, review status and real GUI controls.' -ForegroundColor Green
} finally {
    $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\')+'\'
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'feedback-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
