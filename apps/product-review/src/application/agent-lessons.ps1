# AGENTS.md keeps saved visual lessons; prompts read the ones for the product or its category.
$script:AgentLessonIntro='Bài học được đúc kết thành nguyên tắc ngắn để áp dụng lần sau, không chép lời phản hồi hoặc kể lịch sử xử lý. Chỉ áp dụng đúng URL/danh mục; yêu cầu mới nhất của người dùng có ưu tiên cao nhất. Comment giữ mã và phạm vi để app đọc, bật/tắt bài học.'
$script:AgentLessonPattern='(?ms)^<!-- app-lessons:start -->\r?\n(?<body>.*?)^<!-- app-lessons:end -->'
function Read-AgentLessons([string]$Path) {
    if(-not $Path -or -not (Test-Path -LiteralPath $Path)){return}
    $content=[IO.File]::ReadAllText($Path)
    $blocks=[regex]::Matches($content,$script:AgentLessonPattern)
    if($blocks.Count -gt 1){throw 'AGENTS.md contains duplicate saved-lesson sections.'}
    if(-not $blocks.Count){if($content.Contains('<!-- app-lessons:start -->')){throw 'Incomplete saved-lesson section in AGENTS.md.'};return}
    $body=$blocks[0].Groups['body'].Value
    $legacy=[regex]::Match($body,'(?ms)^```json\r?\n(?<json>.*?)^```')
    if($legacy.Success){
        $records=@(ConvertFrom-Json -InputObject $legacy.Groups['json'].Value)
    }else{
        $items=[regex]::Matches($body,'(?ms)^### (?<title>[^\r\n]+)\r?\n<!-- app-lesson: (?<meta>[^\r\n]+) -->\r?\n(?<text>.*?)(?=^### |\z)')
        if($items.Count -ne [regex]::Matches($body,'<!-- app-lesson:').Count){throw 'Incomplete Markdown lesson.'}
        $records=@(foreach($item in $items){
            $record=ConvertFrom-Json -InputObject $item.Groups['meta'].Value
            $bullets=@([regex]::Matches($item.Groups['text'].Value,'(?m)^- .+')|ForEach-Object{$_.Value.TrimEnd()})
            if(-not $bullets.Count){throw 'Saved lessons require bullet points.'}
            $record|Add-Member NoteProperty title $item.Groups['title'].Value -Force
            $record|Add-Member NoteProperty requested_change ($bullets -join "`n") -Force
            $record
        })
    }
    $seen=@{}
    foreach($record in $records){
        if(-not $record.id -or $seen.ContainsKey($record.id) -or $record.scope -notin @('product','category') -or -not $record.requested_change -or $record.requested_change.Length -gt 4000){throw 'Invalid saved lesson in AGENTS.md.'}
        $seen[$record.id]=$true
        $record
    }
}

