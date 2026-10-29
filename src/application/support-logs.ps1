# Gửi log: one zip with everything needed to look into a problem, uploaded to the management page.
#   summary.txt       the short version: app, setup steps, last runs, latest errors
#   app.json          version, install (git commit or ZIP), system, locale, time zone, memory, disk, screens
#   tools.json        Node, npm, Codex, Git, PowerShell: path and version
#   setup-check.json  the Kiểm tra cấu hình result
#   config.json       app password saved or not (never the password), danh mục, library sync state, samples
#   queue/            the product links and the images attached to them (file names, no images)
#   logs/             workspace/logs: errors from the windows, the Mac server and PowerShell, run logs
#   runs/<id>/        the last 10 runs, every file but the images: results, decisions, inputs, logs, manifests
#   rejected/         reviews marked Bỏ not sent yet, images included, as data to improve the images
# Never included: drive.json (the app password), the Codex sign-in, any other image.
# Returns the zip and the samples it carries.
$script:SupportImageTypes = @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp')

function New-SupportLogBundle([string]$ProjectRoot) {
    $workspace = Join-Path $ProjectRoot 'workspace'
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $system = if (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows) { 'windows' } else { 'mac' }
    $version = try { Get-AppVersion $ProjectRoot } catch { '' }
    $machine = ([Environment]::MachineName -replace '[^\w-]', '')
    $name = (@($stamp, $version, $system, $machine) | Where-Object { $_ }) -join '_'
    $folder = Join-Path ([IO.Path]::GetTempPath()) "prb-log-$([Guid]::NewGuid().ToString('N'))"
    $content = Join-Path $folder $name
    New-Item -ItemType Directory -Force -Path $content | Out-Null
    try {
        $info = Get-SupportSystemInfo $ProjectRoot $version $system $machine
        Save-SupportJson (Join-Path $content 'app.json') $info
        Save-SupportJson (Join-Path $content 'tools.json') (Get-SupportToolInfo)
        $check = Join-Path $ProjectRoot 'src/setup-check.ps1'
        $setup = try { & $check -AsJson 2>&1 | Out-String } catch { $_ | Out-String }
        Set-Content -LiteralPath (Join-Path $content 'setup-check.json') -Value $setup -Encoding UTF8
        $rejected = @(Get-UnsentRejectedSamples $ProjectRoot)
        Save-SupportJson (Join-Path $content 'config.json') (Get-SupportConfig $ProjectRoot $rejected.Count)
        foreach ($file in @('urls.txt', 'reference-inputs/references.json')) {
            $path = Join-Path $workspace $file
            if (Test-Path -LiteralPath $path) { New-Item -ItemType Directory -Force -Path (Join-Path $content 'queue') | Out-Null; Copy-Item -LiteralPath $path -Destination (Join-Path $content 'queue') }
        }
        # App logs, newest first, then the runs, within about 30 MB in all; a very large file keeps its last 2 MB.
        $room = @{ Left = 30MB }
        $logs = Join-Path $workspace 'logs'
        if (Test-Path -LiteralPath $logs) {
            New-Item -ItemType Directory -Force -Path (Join-Path $content 'logs') | Out-Null
            foreach ($file in @(Get-ChildItem -LiteralPath $logs -File | Sort-Object LastWriteTime -Descending | Select-Object -First 60)) {
                Copy-SupportFile $file.FullName (Join-Path $content "logs/$($file.Name)") $room
            }
        }
        # The last runs, every file except the images (results, decisions, inputs, logs, each item's manifest).
        $output = Join-Path $workspace 'output'
        $runs = @(if (Test-Path -LiteralPath $output) { Get-ChildItem -LiteralPath $output -Directory | Sort-Object Name -Descending | Select-Object -First 10 })
        foreach ($batch in $runs) {
            $base = $batch.FullName.TrimEnd('\', '/').Length + 1
            foreach ($file in @(Get-ChildItem -LiteralPath $batch.FullName -File -Recurse | Where-Object { $script:SupportImageTypes -notcontains $_.Extension.ToLowerInvariant() })) {
                Copy-SupportFile $file.FullName (Join-Path $content "runs/$($batch.Name)/$($file.FullName.Substring($base))") $room
            }
        }
        $summary = Get-SupportSummary $info $setup $runs (Join-Path $logs 'app-errors.log')
        # Samples marked Bỏ fill what is left of about 45 MB (uploads stop at 50 MB); the rest go with the next Gửi log.
        $budget = 45MB - [long](Get-ChildItem -LiteralPath $content -File -Recurse | Measure-Object Length -Sum).Sum
        $samples = @()
        foreach ($sample in $rejected) {
            $size = [long](Get-ChildItem -LiteralPath $sample.FullName -File | Measure-Object Length -Sum).Sum
            if ($samples.Count -and $size -gt $budget) { break }
            New-Item -ItemType Directory -Force -Path (Join-Path $content 'rejected') | Out-Null
            Copy-Item -LiteralPath $sample.FullName -Destination (Join-Path $content 'rejected') -Recurse
            $samples += $sample.FullName; $budget -= $size
        }
        $summary += "Ảnh đã Bỏ gửi kèm lần này: $($samples.Count) (có $($rejected.Count) ảnh chưa gửi)"
        [IO.File]::WriteAllText((Join-Path $content 'summary.txt'), ($summary -join "`r`n"), [Text.UTF8Encoding]::new($true))
        $zip = Join-Path $workspace "temp/$name.zip"
        New-Item -ItemType Directory -Force -Path (Split-Path $zip -Parent) | Out-Null
        Compress-Archive -Path $content -DestinationPath $zip -Force
        return [pscustomobject]@{ Path = $zip; Samples = $samples }
    } finally { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

function Save-SupportJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 6), [Text.UTF8Encoding]::new($false))
}

function Copy-SupportFile([string]$From, [string]$To, $Room) {
    $length = (Get-Item -LiteralPath $From).Length
    $keep = if ($length -le 5MB) { $length } else { 2MB }
    if ($keep -gt $Room.Left) { return }
    $Room.Left -= $keep
    New-Item -ItemType Directory -Force -Path (Split-Path $To -Parent) | Out-Null
    if ($length -le 5MB) { Copy-Item -LiteralPath $From -Destination $To; return }
    $stream = [IO.File]::Open($From, 'Open', 'Read', 'ReadWrite')
    try {
        $tail = New-Object byte[] (2MB); [void]$stream.Seek(-2MB, 'End'); [void]$stream.Read($tail, 0, $tail.Length)
        [IO.File]::WriteAllBytes($To, $tail)
    } finally { $stream.Dispose() }
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
