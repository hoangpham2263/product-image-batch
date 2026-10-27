# AGENTS.md is the source of saved visual lessons; feedback folders hold run history.
$script:AgentLessonIntro=@'
Đây là các bài học đang bật mà app đọc trực tiếp trước khi tạo ảnh. Chỉ áp dụng khi khớp URL sản phẩm (`product`) hoặc mã danh mục (`category`); phản hồi sửa hiện tại được ưu tiên hơn bài học cũ. Nội dung phải tự đủ nghĩa, không cần ảnh hoặc log của lượt cũ.

Khối JSON bên dưới là dữ liệu của app, không phải lịch sử chat. Giữ nguyên tên các trường kỹ thuật để app đọc và bật/tắt được:

- `id`: mã ổn định của bài học, dùng để cập nhật hoặc bật/tắt, không phải đường dẫn ảnh.
- `scope`: `product` cho một URL, `category` cho cả danh mục.
- `product_url`: URL áp dụng khi phạm vi là sản phẩm; để trống khi phạm vi là danh mục.
- `category`: mã danh mục trong catalog, không phải tên thư mục kho ảnh tiếng Việt.
- `requested_change`: bài học bằng tiếng Việt, nêu lỗi/yêu cầu và hành vi đúng; không chỉ chép câu nhận xét thiếu ngữ cảnh.
- `created_at`: thời điểm ghi nhận, dùng sắp thứ tự; không phải trạng thái ảnh đã được duyệt.

Bài học có mặt trong danh sách nghĩa là đang bật. App lấy tối đa 10 bài học khớp, từ cũ đến mới. Tắt bài học trong app sẽ gỡ bản ghi khỏi mục này; lịch sử phản hồi và trạng thái duyệt ảnh được giữ riêng trong workspace.
'@
$script:AgentLessonPattern='(?ms)^<!-- app-lessons:start -->\r?\n.*?^```json\r?\n(?<json>.*?)^```\r?\n<!-- app-lessons:end -->'
function Read-AgentLessons([string]$Path) {
    if(-not $Path -or -not (Test-Path -LiteralPath $Path)){return}
    $content=[IO.File]::ReadAllText($Path)
    $blocks=[regex]::Matches($content,$script:AgentLessonPattern)
    if($blocks.Count -gt 1){throw 'AGENTS.md contains duplicate saved-lesson sections.'}
    if(-not $blocks.Count){if($content.Contains('<!-- app-lessons:start -->')){throw 'Incomplete saved-lesson section in AGENTS.md.'};return}
    try{$records=ConvertFrom-Json -InputObject $blocks[0].Groups['json'].Value}catch{throw 'Invalid saved-lesson JSON in AGENTS.md.'}
    $seen=@{}
    foreach($record in $records){
        if(-not $record.id -or $seen.ContainsKey($record.id) -or $record.scope -notin @('product','category') -or -not $record.requested_change -or $record.requested_change.Length -gt 4000){throw 'Invalid saved lesson in AGENTS.md.'}
        $seen[$record.id]=$true
        $record
    }
}

function Set-AgentLesson([string]$ProjectRoot,$Record) {
    $path=Join-Path $ProjectRoot 'AGENTS.md'
    $workspace=Join-Path $ProjectRoot 'workspace'
    New-Item -ItemType Directory -Path $workspace -Force|Out-Null
    $lock=[IO.File]::Open((Join-Path $workspace 'agent-lessons.lock'),'OpenOrCreate','ReadWrite','None')
    try{
        $records=@(Read-AgentLessons $path)
        if(-not $Record.remember -and -not @($records|Where-Object id -eq $Record.id).Count){return}
        $records=@($records|Where-Object id -ne $Record.id)
        if($Record.remember){
            $records+=@([pscustomobject][ordered]@{id=$Record.id;scope=$Record.scope;product_url=$Record.product_url;category=$Record.category;requested_change=$Record.requested_change;created_at=$Record.created_at})
        }
        $json=ConvertTo-Json -InputObject @($records|Sort-Object created_at,id) -Depth 6
        $section='<!-- app-lessons:start -->'+"`r`n"+'## Bài học đã lưu'+"`r`n`r`n"+
            $script:AgentLessonIntro+"`r`n`r`n"+
            '```json'+"`r`n"+$json+"`r`n"+'```'+"`r`n"+'<!-- app-lessons:end -->'
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
