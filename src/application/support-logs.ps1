# Gửi log: one small error report (docs/error-report.md), the same shape every time so an AI can read and check it.
#   report.json   format prb-error-report/1: app, tools, setup check, config, and only the errors since the last
#                 Gửi log (first time: 7 days): app errors, error lines of the logs and runs, reviews marked Bỏ with
#                 the reason typed when rejecting them
#   summary.txt   the same in a few lines for a person
# No images and never drive.json (the app password) or the Codex sign-in. Packed as one ZIP so the upload and the
# management page stay the same. Returns the zip and the Bỏ samples it reports.
$script:SupportImageTypes = @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp')
$script:SupportErrorPattern = '(?i)error|exception|failed|fatal|lỗi|thất bại|không (tải|tạo|đọc|gửi) được|\[CAUSE:'

function New-SupportLogBundle([string]$ProjectRoot) {
    $workspace = Join-Path $ProjectRoot 'workspace'
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $system = if (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows) { 'windows' } else { 'mac' }
    $version = try { Get-AppVersion $ProjectRoot } catch { '' }
    $machine = ([Environment]::MachineName -replace '[^\w-]', '')
    $name = (@($stamp, $version, $system, $machine) | Where-Object { $_ }) -join '_'
    $zip = Join-Path $workspace "temp/$name.zip"
    New-Item -ItemType Directory -Force -Path (Split-Path $zip -Parent) | Out-Null
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    $bundle = @{ Archive = $archive; Root = $name; Size = 0L; Skipped = [Collections.Generic.List[string]]::new() }
    $done = $false
    try {
        $since = Get-SupportLogSince $ProjectRoot
        $info = Get-SupportSystemInfo $ProjectRoot $version $system $machine
        $check = Join-Path $ProjectRoot 'src/setup-check.ps1'
        $setup = try { & $check -AsJson 2>&1 | Out-String } catch { $_ | Out-String }
        $rejected = @(Get-UnsentRejectedSamples $ProjectRoot)
        $logs = Join-Path $workspace 'logs'
        $errors = [Collections.Generic.List[object]]::new()
        # App errors are errors through and through: their last 20 KB since the last Gửi log.
        $appErrors = Join-Path $logs 'app-errors.log'
        if ((Test-Path -LiteralPath $appErrors) -and (Get-Item -LiteralPath $appErrors).LastWriteTime -ge $since) {
            $text = Get-SupportTail $appErrors 20KB
            if ($text.Trim()) { $errors.Add([ordered]@{ source = 'logs/app-errors.log'; text = $text.Trim() }) }
        }
        # Other logs and the runs since then: only their error lines (the last 50 of each file).
        $files = @(if (Test-Path -LiteralPath $logs) { Get-ChildItem -LiteralPath $logs -File | Where-Object { $_.Name -ne 'app-errors.log' -and $_.LastWriteTime -ge $since } | ForEach-Object { @{ Source = "logs/$($_.Name)"; File = $_ } } })
        $output = Join-Path $workspace 'output'
        $all = @(if (Test-Path -LiteralPath $output) { Get-ChildItem -LiteralPath $output -Directory | Sort-Object Name -Descending })
        $runs = @($all | Select-Object -First 10 | Where-Object { $_.LastWriteTime -ge $since })
        if (-not $runs.Count -and $all.Count) { $runs = @($all[0]) }
        foreach ($batch in $runs) {
            $base = $batch.FullName.TrimEnd('\', '/').Length + 1
            $files += @(Get-ChildItem -LiteralPath $batch.FullName -File -Recurse | Where-Object { $_.Extension -in '.log', '.txt', '.json' -and $_.Length -lt 5MB } |
                ForEach-Object { @{ Source = "runs/$($batch.Name)/$($_.FullName.Substring($base) -replace '\\', '/')"; File = $_ } })
        }
        foreach ($f in $files) {
            try {
                $lines = @((Get-SupportTail $f.File.FullName 2MB) -split '\r?\n' | Where-Object { $_ -match $script:SupportErrorPattern } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Last 50)
                if ($lines.Count) { $errors.Add([ordered]@{ source = $f.Source; lines = $lines }) }
            } catch { $bundle.Skipped.Add("$($f.Source)`t$($_.Exception.Message)") }
        }
        $samples = @($rejected | ForEach-Object {
            $json = Join-Path $_.FullName 'sample.json'
            $sample = if (Test-Path -LiteralPath $json) { Get-Content -LiteralPath $json -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{ id = $_.Name } }
            [ordered]@{ run = $sample.run; id = $sample.id; product_handle = $sample.product_handle; reason = [string]$sample.reason; body = $sample.body; decided_at = $sample.decided_at }
        })
        $setupJson = try { $setup | ConvertFrom-Json } catch { $setup }
        $report = [ordered]@{
            format = 'prb-error-report/1'; created_at = (Get-Date).ToString('o'); since = $since.ToString('o')
            app = $info; tools = Get-SupportToolInfo; setup = $setupJson; config = Get-SupportConfig $ProjectRoot $rejected.Count
            runs = @($runs | ForEach-Object Name); errors = $errors.ToArray(); rejected = $samples; skipped = $bundle.Skipped.ToArray()
        }
        Add-SupportText $bundle 'report.json' (ConvertTo-Json -InputObject $report -Depth 8)
        $summary = Get-SupportSummary $info $setup $runs $appErrors
        $summary += "Lỗi từ: $($since.ToString('yyyy-MM-dd HH:mm')) · $($errors.Count) nguồn có lỗi"
        $summary += "Ảnh đã Bỏ báo kèm: $($samples.Count)$(if (@($samples | Where-Object reason).Count) { " (có lý do: $(@($samples | Where-Object reason).Count))" })"
        Add-SupportText $bundle 'summary.txt' ($summary -join "`r`n") -Bom
        $done = $true
        return [pscustomobject]@{ Path = $zip; Samples = @($rejected | ForEach-Object FullName) }
    } finally {
        $archive.Dispose()
        if (-not $done) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
    }
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

# Logs since the last sent Gửi log, with an hour of overlap; the first time, the last 7 days.
function Get-SupportLogSince([string]$ProjectRoot) {
    $mark = Join-Path $ProjectRoot 'workspace/support-sent.txt'
    $last = try { [datetime]::Parse((Get-Content -LiteralPath $mark -Raw).Trim(), [Globalization.CultureInfo]::InvariantCulture, 'RoundtripKind') } catch { $null }
    if ($last) { return $last.ToLocalTime().AddHours(-1) }
    return (Get-Date).AddDays(-7)
}

# After an upload, the next Gửi log starts from now.
function Complete-SupportLogSend([string]$ProjectRoot) {
    [IO.File]::WriteAllText((Join-Path $ProjectRoot 'workspace/support-sent.txt'), (Get-Date).ToUniversalTime().ToString('o'))
}

function Add-SupportText($Bundle, [string]$Entry, [string]$Text, [switch]$Bom) {
    $bytes = [byte[]](@([Text.UTF8Encoding]::new([bool]$Bom).GetPreamble()) + @([Text.Encoding]::UTF8.GetBytes($Text)))
    $stream = $Bundle.Archive.CreateEntry("$($Bundle.Root)/$Entry", [IO.Compression.CompressionLevel]::Optimal).Open()
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    $Bundle.Size += $bytes.Length
}

# Every value is best effort: a missing tool or permission leaves that field empty, never stops Gửi log.
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

function Get-SupportSummary($Info, [string]$Setup, $Runs, [string]$ErrorLog) {
    $lines = @("Product Review Batch $($Info.version) · $($Info.system) · $($Info.machine) · $($Info.created_at)",
        "Cài: $($Info.install)$(if ($Info.git_commit) { " $($Info.git_commit), $($Info.git_changed_files) file sửa" }) · $($Info.os) · $($Info.powershell)", '', 'Kiểm tra cấu hình:')
    $steps = try { @(($Setup | ConvertFrom-Json).Steps) } catch { @() }
    $lines += @(if ($steps.Count) { $steps | ForEach-Object { "  $($_.Title): $($_.State) · $($_.Detail)" } } else { '  (không chạy được, xem setup-check.json)' })
    $lines += @('', 'Lần chạy gần nhất:')
    foreach ($batch in @($Runs)) {
        $items = @(try { Get-BatchReview $batch.FullName } catch { })
        $errors = Join-Path $batch.FullName 'logs/run.err.log'
        $errorLines = if (Test-Path -LiteralPath $errors) { @(Get-Content -LiteralPath $errors -Encoding UTF8 | Where-Object { $_.Trim() }).Count } else { 0 }
        $lines += "  $($batch.Name): $($items.Count) ảnh · giữ $(@($items | Where-Object Decision -eq 'ok').Count) · bỏ $(@($items | Where-Object Decision -eq 'bad').Count) · chưa duyệt $(@($items | Where-Object { -not $_.Decision }).Count) · $errorLines dòng lỗi"
    }
    if (-not @($Runs).Count) { $lines += '  (chưa có)' }
    $lines += @('', 'Lỗi gần nhất (logs/app-errors.log):')
    $recent = @(if (Test-Path -LiteralPath $ErrorLog) { Get-Content -LiteralPath $ErrorLog -Encoding UTF8 | Where-Object { $_ -match '^\[' } | Select-Object -Last 5 })
    $lines += @(if ($recent.Count) { $recent | ForEach-Object { "  $_" } } else { '  (không có)' })
    return @($lines + '')
}

function Send-SupportLog($Drive, [string]$ZipPath) {
    $name = [Uri]::EscapeDataString([IO.Path]::GetFileName($ZipPath))
    Invoke-RestMethod -Uri "$($Drive.ApiUrl)/api/logs?name=$name" -Method Post -ContentType 'application/zip' -Headers @{ 'x-admin-key' = $Drive.AdminKey } -InFile $ZipPath -TimeoutSec 300 | Out-Null
    return [IO.Path]::GetFileName($ZipPath)
}
