# Gửi lỗi: one file only, <stamp>_<version>_<system>_<machine>.md, uploaded to the management page.
# The app gathers what went wrong since the last Gửi lỗi (first time: 7 days): failed setup steps, app errors, the
# error lines of its logs and runs, and the reviews marked Bỏ with the reason typed. With -Analyze, Codex CLI turns
# that into the error file by docs/error-report.md (cause, fix, what to change in the app); without Codex (missing,
# signed out, offline, over 2 minutes) the app writes the same facts itself. No images, never drive.json (the app
# password) or the Codex sign-in. Returns the file and the Bỏ samples it reports.
$script:SupportImageTypes = @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp')
$script:SupportErrorPattern = '(?i)error|exception|failed|fatal|lỗi|thất bại|không (tải|tạo|đọc|gửi) được|\[CAUSE:'

# $OnStep gets each step's text for the progress shown in the app.
function New-SupportLogBundle([string]$ProjectRoot, [switch]$Analyze, [scriptblock]$OnStep) {
    $workspace = Join-Path $ProjectRoot 'workspace'
    $system = if (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows) { 'windows' } else { 'mac' }
    $version = try { Get-AppVersion $ProjectRoot } catch { '' }
    $machine = ([Environment]::MachineName -replace '[^\w-]', '')
    $name = (@((Get-Date -Format 'yyyy-MM-dd_HHmmss'), $version, $system, $machine) | Where-Object { $_ }) -join '_'
    $file = Join-Path $workspace "temp/$name.md"
    New-Item -ItemType Directory -Force -Path (Split-Path $file -Parent) | Out-Null
    if ($OnStep) { & $OnStep 'Đang gom lỗi…' }
    $since = Get-SupportLogSince $ProjectRoot
    $info = Get-SupportSystemInfo $ProjectRoot $version $system $machine
    $check = Join-Path $ProjectRoot 'src/setup-check.ps1'
    $setup = try { & $check -AsJson 2>&1 | Out-String } catch { $_ | Out-String }
    $steps = @(try { @(($setup | ConvertFrom-Json).Steps) } catch { })
    $rejected = @(Get-UnsentRejectedSamples $ProjectRoot)
    $logs = Join-Path $workspace 'logs'
    $errors = [Collections.Generic.List[object]]::new()
    # App errors are errors through and through: their last 20 KB since the last Gửi lỗi.
    $appErrors = Join-Path $logs 'app-errors.log'
    if ((Test-Path -LiteralPath $appErrors) -and (Get-Item -LiteralPath $appErrors).LastWriteTime -ge $since) {
        $text = (Get-SupportTail $appErrors 20KB).Trim()
        if ($text) { $errors.Add([ordered]@{ source = 'logs/app-errors.log'; at = (Get-Item -LiteralPath $appErrors).LastWriteTime.ToString('yyyy-MM-dd HH:mm'); lines = @($text -split '\r?\n') }) }
    }
    # Other logs and the runs since then: only their error lines (the last 50 of each file).
    $files = @(if (Test-Path -LiteralPath $logs) { Get-ChildItem -LiteralPath $logs -File | Where-Object { $_.Name -ne 'app-errors.log' -and $_.LastWriteTime -ge $since } | ForEach-Object { @{ Source = "logs/$($_.Name)"; File = $_ } } })
    $output = Join-Path $workspace 'output'
    $runs = @(if (Test-Path -LiteralPath $output) { Get-ChildItem -LiteralPath $output -Directory | Sort-Object Name -Descending | Select-Object -First 10 | Where-Object { $_.LastWriteTime -ge $since } })
    foreach ($batch in $runs) {
        $base = $batch.FullName.TrimEnd('\', '/').Length + 1
        $files += @(Get-ChildItem -LiteralPath $batch.FullName -File -Recurse | Where-Object { $_.Extension -in '.log', '.txt', '.json' -and $_.Length -lt 5MB } |
            ForEach-Object { @{ Source = "runs/$($batch.Name)/$($_.FullName.Substring($base) -replace '\\', '/')"; File = $_ } })
    }
    foreach ($f in $files) {
        try {
            $lines = @((Get-SupportTail $f.File.FullName 2MB) -split '\r?\n' | Where-Object { $_ -match $script:SupportErrorPattern } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Last 50)
            if ($lines.Count) { $errors.Add([ordered]@{ source = $f.Source; at = $f.File.LastWriteTime.ToString('yyyy-MM-dd HH:mm'); lines = $lines }) }
        } catch { Write-Verbose $_ }
    }
    $samples = @($rejected | ForEach-Object {
        $json = Join-Path $_.FullName 'sample.json'
        $sample = if (Test-Path -LiteralPath $json) { Get-Content -LiteralPath $json -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{ id = $_.Name } }
        [ordered]@{ run = $sample.run; id = $sample.id; product = $sample.product_handle; reason = [string]$sample.reason; body = $sample.body; at = $(try { ([datetime]$sample.decided_at).ToString('yyyy-MM-dd HH:mm') } catch { '' }) }
    })
    $facts = [ordered]@{ app = $info; tools = Get-SupportToolInfo; since = $since.ToString('o'); setup = @($steps | Where-Object { $_.State -ne 'ok' }); config = Get-SupportConfig $ProjectRoot $rejected.Count
        errors = $errors.ToArray(); rejected = $samples }
    $title = "# Lỗi Product Review Batch $version · $system · $machine · $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $body = ''
    if ($Analyze -and ($errors.Count -or $samples.Count -or @($facts.setup).Count)) {
        if ($OnStep) { & $OnStep 'AI đang viết file lỗi (tối đa 2 phút)…' }
        $body = Get-SupportAnalysis $ProjectRoot (ConvertTo-Json -InputObject $facts -Depth 8)
    }
    if (-not $body) { $body = ConvertTo-SupportErrorText $facts }
    [IO.File]::WriteAllText($file, "$title`n`n$body`n", [Text.UTF8Encoding]::new($true))
    return [pscustomobject]@{ Path = $file; Samples = @($rejected | ForEach-Object FullName) }
}

# The error file without AI: the same facts, as short lists.
function ConvertTo-SupportErrorText($Facts) {
    $out = [Collections.Generic.List[string]]::new()
    $out.Add("Từ $(([datetime]$Facts.since).ToString('yyyy-MM-dd HH:mm')) · cài $($Facts.app.install) · $($Facts.app.os)")
    if (@($Facts.setup).Count) { $out.Add(''); $out.Add('## Cấu hình chưa đạt'); foreach ($s in $Facts.setup) { $out.Add("- $($s.Title): $($s.Detail)") } }
    if (@($Facts.errors).Count) {
        $out.Add(''); $out.Add('## Lỗi')
        foreach ($e in $Facts.errors) { $out.Add("### $($e.source) · $($e.at)"); foreach ($l in @($e.lines | Select-Object -Last 20)) { $out.Add("- $l") } }
    }
    if (@($Facts.rejected).Count) {
        $out.Add(''); $out.Add('## Đánh giá đã Bỏ')
        foreach ($r in $Facts.rejected) { $out.Add("- $($r.at) · $($r.run) / $($r.id)$(if ($r.product) { " ($($r.product))" }): $(if ($r.reason) { $r.reason } else { 'không ghi lý do' })") }
    }
    if ($out.Count -eq 1) { $out.Add(''); $out.Add('Không có lỗi nào từ lần gửi trước.') }
    return ($out -join "`n")
}

# Codex CLI writes the error file by the standard (docs/error-report.md): read-only, low effort, at most 2 minutes.
# '' when it cannot (not installed, signed out, offline, too slow): the app writes the facts itself.
function Get-SupportAnalysis([string]$ProjectRoot, [string]$ReportText) {
    try {
        $guide = Get-Content -LiteralPath (Join-Path $ProjectRoot 'docs/error-report.md') -Raw -Encoding UTF8
        $temp = Join-Path $ProjectRoot 'workspace/temp'
        $out = Join-Path $temp ('analysis-' + [Guid]::NewGuid().ToString('N') + '.md')
        $prompt = "$guide`n`nViết file lỗi theo chuẩn trên (mục Nội dung file) từ dữ liệu dưới đây. Chỉ trả về nội dung, bắt đầu từ ## Tóm tắt, không có dòng # đầu.`n`n``````json`n$ReportText`n``````"
        $execution = Invoke-CodexProcess $prompt @('exec', '--skip-git-repo-check', '-s', 'read-only', '-C', $temp, '-c', 'model_reasoning_effort=low', '-o', $out) "$out.console.log" 120
        $text = if ($execution.ExitCode -eq 0 -and (Test-Path -LiteralPath $out)) { [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8).Trim() } else { '' }
        return $text
    } catch { return '' }
    finally { if ($out) { Remove-Item -LiteralPath $out, "$out.console.log" -Force -ErrorAction SilentlyContinue } }
}

# The end of a text file (shared read, so a log being written is fine).
function Get-SupportTail([string]$Path, [long]$Bytes) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        if ($stream.Length -gt $Bytes) { [void]$stream.Seek(-$Bytes, 'End') }
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
        return $reader.ReadToEnd()
    } finally { $stream.Dispose() }
}

# Logs since the last sent Gửi lỗi, with an hour of overlap; the first time, the last 7 days.
function Get-SupportLogSince([string]$ProjectRoot) {
    $mark = Join-Path $ProjectRoot 'workspace/support-sent.txt'
    $last = try { [datetime]::Parse((Get-Content -LiteralPath $mark -Raw).Trim(), [Globalization.CultureInfo]::InvariantCulture, 'RoundtripKind') } catch { $null }
    if ($last) { return $last.ToLocalTime().AddHours(-1) }
    return (Get-Date).AddDays(-7)
}

# After an upload, the next Gửi lỗi starts from now.
function Complete-SupportLogSend([string]$ProjectRoot) {
    [IO.File]::WriteAllText((Join-Path $ProjectRoot 'workspace/support-sent.txt'), (Get-Date).ToUniversalTime().ToString('o'))
}

# Every value is best effort: a missing tool or permission leaves that field empty, never stops Gửi lỗi.
function Get-SupportSystemInfo([string]$ProjectRoot, [string]$Version, [string]$System, [string]$Machine) {
    $try = { param($Block) try { & $Block } catch { '' } }
    $git = Test-Path -LiteralPath (Join-Path $ProjectRoot '.git')
    $info = [ordered]@{
        created_at = (Get-Date).ToString('o'); version = $Version; system = $System; machine = $Machine; root = $ProjectRoot
        install = $(if ($git) { 'git' } else { 'zip' })
        git_commit = $(if ($git) { & $try { [string](git -C $ProjectRoot rev-parse --short HEAD 2>$null) } } else { '' })
        git_changed_files = $(if ($git) { & $try { @(git -C $ProjectRoot status --porcelain 2>$null).Count } } else { '' })
        os = [Environment]::OSVersion.VersionString
        powershell = "$($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition)"
        dotnet = & $try { [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription }
        culture = & $try { (Get-Culture).Name }; time_zone = & $try { [TimeZoneInfo]::Local.Id }
        processors = [Environment]::ProcessorCount
        disk_free_gb = & $try { $full = [IO.Path]::GetFullPath($ProjectRoot); [Math]::Round((@([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $full.StartsWith($_.RootDirectory.FullName, [StringComparison]::OrdinalIgnoreCase) } | Sort-Object { $_.RootDirectory.FullName.Length } -Descending)[0].AvailableFreeSpace / 1GB), 1) }
    }
    if ($System -eq 'windows') {
        $computer = & $try { Get-CimInstance Win32_ComputerSystem }
        $info.model = & $try { "$($computer.Manufacturer) $($computer.Model)" }
        $info.memory_gb = & $try { [Math]::Round($computer.TotalPhysicalMemory / 1GB, 1) }
        $info.screens = & $try {
            Add-Type -AssemblyName System.Windows.Forms, System.Drawing
            $graphics = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
            try { $dpi = $graphics.DpiX } finally { $graphics.Dispose() }
            @([Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.Bounds.Width)x$($_.Bounds.Height)$(if ($_.Primary) { ' chính' }) · $([int]$dpi) dpi ($([int]($dpi / 96 * 100))%)" })
        }
    } else {
        $info.os = & $try { "macOS $((sw_vers -productVersion).Trim()) ($((sw_vers -buildVersion).Trim())) · $(uname -m)" }
        $info.model = & $try { (sysctl -n hw.model).Trim() }
        $info.memory_gb = & $try { [Math]::Round([double](sysctl -n hw.memsize) / 1GB, 1) }
    }
    return $info
}

function Get-SupportToolInfo {
    $tools = [ordered]@{}
    foreach ($tool in @('node', 'npm', 'codex', 'git', 'pwsh', 'winget', 'brew')) {
        $command = @(Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue)[0]
        $tools[$tool] = if ($command) {
            [ordered]@{ path = $command.Source; version = $(try { [string](@(& $command.Source --version 2>&1)[0]) } catch { '' }) }
        } else { $null }
    }
    return $tools
}

function Get-SupportConfig([string]$ProjectRoot, [int]$Unsent) {
    $workspace = Join-Path $ProjectRoot 'workspace'
    $readJson = { param($Path) if (Test-Path -LiteralPath $Path) { try { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { 'không đọc được' } } }
    $drive = & $readJson (Join-Path $workspace 'drive.json')
    $library = Join-Path $ProjectRoot 'data/source-photos'
    $groups = @(if (Test-Path -LiteralPath $library) {
            Get-ChildItem -LiteralPath $library -Directory | ForEach-Object {
                $index = Join-Path $_.FullName '.drive-sync.json'
                [ordered]@{ name = $_.Name; files = @(Get-ChildItem -LiteralPath $_.FullName -File | Where-Object { $script:SupportImageTypes -contains $_.Extension.ToLowerInvariant() }).Count
                    synced = $(if (Test-Path -LiteralPath $index) { try { @((Get-Content -LiteralPath $index -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties).Count } catch { -1 } } else { 0 }) }
            }
        })
    $rejectedRoot = Join-Path $workspace 'rejected'
    return [ordered]@{
        app_password_saved = [bool]($drive -and $drive.adminKey)
        api_url = $(if ($drive) { [string]$drive.apiUrl } else { '' })
        version_file = $(if (Test-Path -LiteralPath (Join-Path $workspace 'version.txt')) { (Get-Content -LiteralPath (Join-Path $workspace 'version.txt') -Raw).Trim() } else { '' })
        ai_model = $(try { Get-AiSettings $ProjectRoot } catch { $null })
        enabled_groups = & $readJson (Join-Path $workspace 'source-groups.json')
        library = $groups
        rejected = [ordered]@{ unsent = $Unsent; total = @(if (Test-Path -LiteralPath $rejectedRoot) { Get-ChildItem -LiteralPath $rejectedRoot -Directory }).Count }
    }
}

function Send-SupportLog($Drive, [string]$Path) {
    $name = [Uri]::EscapeDataString([IO.Path]::GetFileName($Path))
    Invoke-RestMethod -Uri "$($Drive.ApiUrl)/api/logs?name=$name" -Method Post -ContentType 'text/markdown; charset=utf-8' -Headers @{ 'x-admin-key' = $Drive.AdminKey } -InFile $Path -TimeoutSec 120 | Out-Null
    return [IO.Path]::GetFileName($Path)
}
