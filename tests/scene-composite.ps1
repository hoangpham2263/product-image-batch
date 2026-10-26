. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/bootstrap.ps1')
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$temp=Join-Path $TestWorkspaceRoot ('scene-composite-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try {
    $room=Join-Path $temp 'room.png';$edit=Join-Path $temp 'edit.png';$mask=Join-Path $temp 'mask.png';$output=Join-Path $temp 'result.png'
    $r=[Drawing.Bitmap]::new(8,6);$e=[Drawing.Bitmap]::new(8,6);$m=[Drawing.Bitmap]::new(8,6)
    for($y=0;$y -lt 6;$y++){for($x=0;$x -lt 8;$x++){
        $r.SetPixel($x,$y,[Drawing.Color]::FromArgb(255,($x*20),($y*25),60))
        $e.SetPixel($x,$y,[Drawing.Color]::Magenta)
        $m.SetPixel($x,$y,[Drawing.Color]::Black)
        if($x -ge 2 -and $x -le 4 -and $y -ge 2 -and $y -le 3){$m.SetPixel($x,$y,[Drawing.Color]::White)}
    }}
    $r.Save($room,[Drawing.Imaging.ImageFormat]::Png);$e.Save($edit,[Drawing.Imaging.ImageFormat]::Png);$m.Save($mask,[Drawing.Imaging.ImageFormat]::Png)
    $r.Dispose();$e.Dispose();$m.Dispose()
    [ProductSceneComposite]::Merge($room,$edit,$mask,$output)
    $original=[Drawing.Bitmap]::new($room);$result=[Drawing.Bitmap]::new($output)
    try {
        for($y=0;$y -lt 6;$y++){for($x=0;$x -lt 8;$x++){
            $inEdit=$x -ge 2 -and $x -le 4 -and $y -ge 2 -and $y -le 3
            $expected=if($inEdit){[Drawing.Color]::Magenta.ToArgb()}else{$original.GetPixel($x,$y).ToArgb()}
            Assert ($result.GetPixel($x,$y).ToArgb() -eq $expected) 'Room pixels changed outside the edit mask, or furniture pixels were not inserted.'
        }}
    } finally {$original.Dispose();$result.Dispose()}
    $fullMask=Join-Path $temp 'full.png';$bad=[Drawing.Bitmap]::new(8,6);$g=[Drawing.Graphics]::FromImage($bad);$g.Clear([Drawing.Color]::White);$g.Dispose();$bad.Save($fullMask,[Drawing.Imaging.ImageFormat]::Png);$bad.Dispose()
    $rejected=$false
    try{[ProductSceneComposite]::Merge($room,$edit,$fullMask,(Join-Path $temp 'bad.png'))}catch{$rejected=$true}
    Assert $rejected 'A full-room redraw mask was accepted.'
    # A resized PNG may have a partial-alpha fringe only on the canvas boundary.
    $fringeEdit=Join-Path $temp 'fringe-edit.png';$fringeMask=Join-Path $temp 'fringe-mask.png'
    $f=[Drawing.Bitmap]::new(8,6);$fm=[Drawing.Bitmap]::new(8,6)
    for($y=0;$y -lt 6;$y++){for($x=0;$x -lt 8;$x++){$f.SetPixel($x,$y,[Drawing.Color]::Magenta);$fm.SetPixel($x,$y,[Drawing.Color]::Black)}}
    $f.SetPixel(3,5,[Drawing.Color]::FromArgb(195,180,90,40));$fm.SetPixel(3,5,[Drawing.Color]::White)
    $f.Save($fringeEdit,[Drawing.Imaging.ImageFormat]::Png);$fm.Save($fringeMask,[Drawing.Imaging.ImageFormat]::Png)
    $fringeOutput=Join-Path $temp 'fringe-result.png';[ProductSceneComposite]::Merge($room,$fringeEdit,$fringeMask,$fringeOutput)
    $check=[Drawing.Bitmap]::new($fringeOutput)
    try{Assert ($check.GetPixel(3,5).A -eq 255 -and $check.GetPixel(3,5).R -eq 180) 'Harmless edge alpha blocked export or changed product RGB.'}finally{$check.Dispose()}
    $f.SetPixel(3,3,[Drawing.Color]::FromArgb(195,180,90,40));$fm.SetPixel(3,3,[Drawing.Color]::White)
    $f.Save($fringeEdit,[Drawing.Imaging.ImageFormat]::Png);$fm.Save($fringeMask,[Drawing.Imaging.ImageFormat]::Png);$f.Dispose();$fm.Dispose()
    $rejected=$false;try{[ProductSceneComposite]::Merge($room,$fringeEdit,$fringeMask,(Join-Path $temp 'bad-interior.png'))}catch{$rejected=$true}
    Assert $rejected 'Interior transparency was silently flattened, hiding an incomplete product.'
    $wrong=Join-Path $temp 'wrong.png';$bad=[Drawing.Bitmap]::new(4,4);$bad.Save($wrong,[Drawing.Imaging.ImageFormat]::Png);$bad.Dispose()
    $rejected=$false
    try{[ProductSceneComposite]::Merge($room,$wrong,$mask,(Join-Path $temp 'bad.png'))}catch{$rejected=$true}
    Assert $rejected 'A resized/reframed output was accepted.'
    $script:Batch=@{Logs=$temp}
    $request=[pscustomobject]@{SceneBase=$room;Output=$edit;EditMask=$mask}
    Merge-ProductIntoScene $request '001-table' 1
    Assert (Test-Path (Join-Path $temp '001-table-attempt-1-generated.png')) 'Original generated output evidence was lost.'
    $context=[pscustomobject]@{product='dining table';details='wood top';setting='dining room';reject='different room';branding='no logo'}
    function Invoke-AI($PromptText,$Images,$ResultFile){
        Assert ($Images.Count -eq 4 -and $Images[2] -eq $room -and $Images[3] -eq $mask) 'Quality check did not receive the actual room and mask.'
        Assert ($PromptText -match 'ORIGINAL LOCKED ROOM' -and $PromptText -match 'EDIT MASK' -and $PromptText -match 'do not reject inherited styling alone') 'Room comparison or mask localization rules missing.'
        Assert ($PromptText -match 'Judge intrinsic material color separately from illumination' -and $PromptText -match 'not itself a defect' -and $PromptText -match 'bleached wood or lost characteristic grain') 'Color QA must permit room lighting without demanding either palette matching or a changed material.'
        Assert ($PromptText -match 'ALL main blocking defects together') 'QA must report concurrent blockers instead of hiding them until another image generation.'
        Assert ($PromptText -match 'A bare tabletop is valid' -and $PromptText -match 'unless explicitly requested by the user') 'Optional scene suggestions must not become mandatory added-prop failures.'
        Assert ($PromptText -match 'ABSENCE IS A CONSTRAINT' -and $PromptText -match 'reject any newly introduced object' -and $PromptText -match 'AI-inferred activities are not user requests') 'QA must reject invented props rather than merely tolerate their absence.'
        return 'PASS'
    }
    Assert ((Test-ProductScene $edit $room $context '001-table' 1 $room $mask) -eq 'PASS') 'Quality comparison failed.'
    $request.EditMask=Join-Path $temp 'missing.png';$rejected=$false
    try{Merge-ProductIntoScene $request '001-table' 2}catch{$rejected=$true}
    Assert $rejected 'Unmasked generated rooms must never be exported.'
    # Exercise the full object path: missing mask is repaired once, then the
    # restored room + mask are compared before the edited photo can be accepted.
    $backup=Join-Path $temp 'mask-backup.png';Copy-Item -LiteralPath $mask -Destination $backup
    $request.EditMask=$mask;Remove-Item -LiteralPath $mask -Force
    $context|Add-Member NoteProperty presentation 'placed'
    $script:GenerationCalls=0
    function Invoke-ImageGeneration($Request,$ItemId,$Attempt,$PreviousQuality){
        $script:GenerationCalls++
        if($Attempt -eq 2){
            Assert ($PreviousQuality -match 'mask is missing') 'Mask repair lost its concrete failure reason.'
            Copy-Item -LiteralPath $backup -Destination $Request.EditMask
        }
        return 'BRAND: none'
    }
    Assert ((Complete-ProductImage $request $room $context '002-table') -eq 'BRAND: none' -and $script:GenerationCalls -eq 2) 'Localized edit was not repaired and validated through the object workflow.'
    Write-Host 'PASS: exact background pixel preservation, bounded masks, fixed dimensions, room comparison and fail-closed export.' -ForegroundColor Green
} finally {
    $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\')+'\'
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'scene-composite-test-*'){
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
