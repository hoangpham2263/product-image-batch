function Save-Csv([object[]]$Rows, [string]$Path) {
    $columns = @('product_handle', 'rating', 'author', 'email', 'body', 'created_at', 'photo_url', 'verified_purchase')
    $temp = "$Path.tmp"
    # Match Loox's downloadable template: plain header, comma separator, UTF-8 without BOM.
    $lines=New-Object Collections.Generic.List[string]
    $lines.Add(($columns -join ','))
    if ($Rows.Count) {
        $exportRows=@(foreach($row in $Rows){
            $values=[ordered]@{}
            foreach($column in $columns){$values[$column]=$row.$column}
            if([string]$values.created_at -match '^\d{4}-\d{2}-\d{2}(?:$|[ T])'){$values.created_at=([string]$values.created_at).Substring(0,10)}
            if([string]$values.verified_purchase -match '^(?i:true|false)$'){$values.verified_purchase=([string]$values.verified_purchase).ToUpperInvariant()}
            [pscustomobject]$values
        })
        foreach($line in @($exportRows|ConvertTo-Csv -NoTypeInformation|Select-Object -Skip 1)){$lines.Add($line)}
    }
    [IO.File]::WriteAllText($temp,($lines -join "`r`n")+"`r`n",[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
