function Save-Csv([object[]]$Rows, [string]$Path) {
    $columns = @('product_handle', 'rating', 'author', 'email', 'body', 'created_at', 'photo_url', 'verified_purchase')
    $temp = "$Path.tmp"
    if ($Rows.Count) { $Rows | Select-Object -Property $columns | Export-Csv -LiteralPath $temp -NoTypeInformation -Encoding UTF8 }
    else { ('"' + ($columns -join '","') + '"') | Set-Content -LiteralPath $temp -Encoding UTF8 }
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
