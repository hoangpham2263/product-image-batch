# Verify PNG readability while preserving the delivered file bytes.
Add-Type -AssemblyName System.Drawing
function Assert-GeneratedImage([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Image technical validation failed: output image is missing.'}
    $image=$null
    try{
        $image=[Drawing.Image]::FromFile($Path)
        if($image.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid){throw 'Output must be a PNG image.'}
    }catch{throw "Image technical validation failed: output image cannot be read as PNG. $($_.Exception.Message)"}
    finally{if($image){$image.Dispose()}}
}
