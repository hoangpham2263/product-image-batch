# AGENTS.md is the source of saved visual lessons; feedback folders hold run history.
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

function New-AgentLessonSection([object[]]$Records) {
    $lines=[Collections.Generic.List[string]]::new()
    foreach($line in @('<!-- app-lessons:start -->','## Bài học đã đúc kết','',$script:AgentLessonIntro,'')){$lines.Add($line)}
    foreach($record in @($Records|Sort-Object created_at,id)){
        $title=if($record.title){$record.title -replace '[\r\n]+',' '}elseif($record.scope -eq 'category'){"Bài học cho danh mục $($record.category)"}else{'Bài học cho sản phẩm'}
        $meta=[ordered]@{id=$record.id;scope=$record.scope;product_url=$record.product_url;category=$record.category;created_at=$record.created_at}
        $lines.Add("### $title")
        $lines.Add('<!-- app-lesson: '+((ConvertTo-Json -InputObject $meta -Compress) -replace '-->','\u002d\u002d\u003e')+' -->')
        $scope=if($record.scope -eq 'product'){$record.product_url}else{'danh mục `'+$record.category+'`'}
        $lines.Add("Áp dụng: $scope.");$lines.Add('')
        foreach($line in @($record.requested_change -split '\r?\n'|Where-Object{$_.Trim()})){
            $lines.Add('- '+(($line.Trim() -replace '^[-*]\s+','') -replace '<!--','&lt;!--'))
        }
        $lines.Add('')
    }
    $lines.Add('<!-- app-lessons:end -->')
    return $lines -join "`r`n"
}

function Set-AgentLesson([string]$ProjectRoot,$Record) {
    $path=Join-Path $ProjectRoot 'AGENTS.md'
    $workspace=Join-Path $ProjectRoot 'workspace'
    New-Item -ItemType Directory -Path $workspace -Force|Out-Null
    $lock=[IO.File]::Open((Join-Path $workspace 'agent-lessons.lock'),'OpenOrCreate','ReadWrite','None')
    try{
        $records=@(Read-AgentLessons $path)
        if(-not $Record.remember -and -not @($records|Where-Object id -eq $Record.id).Count){return}
        $existing=@($records|Where-Object id -eq $Record.id)
        $records=@($records|Where-Object id -ne $Record.id)
        if($Record.remember){
            $title=if($Record.title){$Record.title}elseif($existing.Count){$existing[0].title}else{''}
            $records+=@([pscustomobject][ordered]@{id=$Record.id;scope=$Record.scope;product_url=$Record.product_url;category=$Record.category;title=$title;requested_change=$Record.requested_change;created_at=$Record.created_at})
        }
        $section=New-AgentLessonSection $records
        $content=if(Test-Path -LiteralPath $path){[IO.File]::ReadAllText($path)}else{"# Project instructions`r`n"}
        $block=[regex]::Match($content,$script:AgentLessonPattern)
        if($block.Success){$content=$content.Substring(0,$block.Index)+$section+$content.Substring($block.Index+$block.Length)}
        else{$content=$content.TrimEnd()+"`r`n`r`n"+$section+"`r`n"}
        $temporary="$path.$([Guid]::NewGuid().ToString('N')).tmp"
        try{[IO.File]::WriteAllText($temporary,$content,[Text.UTF8Encoding]::new($true));Move-Item -LiteralPath $temporary -Destination $path -Force}
        finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
    }finally{$lock.Dispose()}
}

function Set-ImageFeedbackRemember([string]$ProjectRoot,[string]$Path,[bool]$Remember) {
    $record=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    $record.remember=$Remember
    Set-AgentLesson $ProjectRoot $record
    Write-FeedbackJson $Path $record
}
