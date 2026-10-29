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
    # Files go straight into the ZIP, never through a staging folder: on Windows without long paths enabled a staged
    # copy (temp + bundle + runs/<run>/refs/<item>/…) easily passes 260 characters, while names inside a ZIP have no
    # such limit. If the upload fails the ZIP stays in workspace/temp for sending by hand.
    $zip = Join-Path $workspace "temp/$name.zip"
    New-Item -ItemType Directory -Force -Path (Split-Path $zip -Parent) | Out-Null
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    $bundle = @{ Archive = $archive; Root = $name; Size = 0L; Skipped = [Collections.Generic.List[string]]::new() }
    $done = $false
    try {
        $info = Get-SupportSystemInfo $ProjectRoot $version $system $machine
        Add-SupportText $bundle 'app.json' (ConvertTo-Json -InputObject $info -Depth 6)
        Add-SupportText $bundle 'tools.json' (ConvertTo-Json -InputObject (Get-SupportToolInfo) -Depth 6)
        $check = Join-Path $ProjectRoot 'src/setup-check.ps1'
        $setup = try { & $check -AsJson 2>&1 | Out-String } catch { $_ | Out-String }
        Add-SupportText $bundle 'setup-check.json' $setup
        $rejected = @(Get-UnsentRejectedSamples $ProjectRoot)
        Add-SupportText $bundle 'config.json' (ConvertTo-Json -InputObject (Get-SupportConfig $ProjectRoot $rejected.Count) -Depth 6)
        foreach ($file in @('urls.txt', 'reference-inputs/references.json')) {
            $path = Join-Path $workspace $file
            if (Test-Path -LiteralPath $path) { Add-SupportFile $bundle "queue/$(Split-Path $path -Leaf)" $path }
        }
        # App logs, newest first, then the runs, within about 30 MB in all; a very large file keeps its last 2 MB.
        $room = @{ Left = 30MB }
        $logs = Join-Path $workspace 'logs'
        if (Test-Path -LiteralPath $logs) {
            foreach ($file in @(Get-ChildItem -LiteralPath $logs -File | Sort-Object LastWriteTime -Descending | Select-Object -First 60)) {
                Add-SupportFile $bundle "logs/$($file.Name)" $file.FullName $room
            }
        }
        # The last runs, every file except the images (results, decisions, inputs, logs, each item's manifest).
        $output = Join-Path $workspace 'output'
        $runs = @(if (Test-Path -LiteralPath $output) { Get-ChildItem -LiteralPath $output -Directory | Sort-Object Name -Descending | Select-Object -First 10 })
        foreach ($batch in $runs) {
            $base = $batch.FullName.TrimEnd('\', '/').Length + 1
            foreach ($file in @(Get-ChildItem -LiteralPath $batch.FullName -File -Recurse | Where-Object { $script:SupportImageTypes -notcontains $_.Extension.ToLowerInvariant() })) {
                Add-SupportFile $bundle "runs/$($batch.Name)/$($file.FullName.Substring($base))" $file.FullName $room
            }
        }
        $summary = Get-SupportSummary $info $setup $runs (Join-Path $logs 'app-errors.log')
        # Samples marked Bỏ fill what is left of about 45 MB (uploads stop at 50 MB); the rest go with the next Gửi log.
        $budget = 45MB - $bundle.Size
        $samples = @()
        foreach ($sample in $rejected) {
            $files = @(Get-ChildItem -LiteralPath $sample.FullName -File)
            $size = [long]($files | Measure-Object Length -Sum).Sum
            if ($samples.Count -and $size -gt $budget) { break }
            foreach ($file in $files) { Add-SupportFile $bundle "rejected/$($sample.Name)/$($file.Name)" $file.FullName }
            $samples += $sample.FullName; $budget -= $size
        }
        $summary += "Ảnh đã Bỏ gửi kèm lần này: $($samples.Count) (có $($rejected.Count) ảnh chưa gửi)"
        if ($bundle.Skipped.Count) { $summary += "Bỏ qua $($bundle.Skipped.Count) file không đọc được (xem skipped.txt)."; Add-SupportText $bundle 'skipped.txt' ($bundle.Skipped -join "`r`n") }
        Add-SupportText $bundle 'summary.txt' ($summary -join "`r`n") -Bom
        $done = $true
        return [pscustomobject]@{ Path = $zip; Samples = $samples }
    } finally {
        $archive.Dispose()
        if (-not $done) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
    }
}

function Add-SupportText($Bundle, [string]$Entry, [string]$Text, [switch]$Bom) {
    $bytes = [byte[]](@([Text.UTF8Encoding]::new([bool]$Bom).GetPreamble()) + @([Text.Encoding]::UTF8.GetBytes($Text)))
    $stream = $Bundle.Archive.CreateEntry("$($Bundle.Root)/$Entry", [IO.Compression.CompressionLevel]::Optimal).Open()
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    $Bundle.Size += $bytes.Length
}

# One file into the ZIP; with $Room, counted against that budget and a file over 5 MB keeps its last 2 MB. A file
# that cannot be read (locked, removed meanwhile) is listed in skipped.txt instead of stopping Gửi log.
function Add-SupportFile($Bundle, [string]$Entry, [string]$From, $Room) {
    try {
        $length = (Get-Item -LiteralPath $From).Length
        $keep = if ($length -le 5MB) { $length } else { 2MB }
        if ($Room) { if ($keep -gt $Room.Left) { return }; $Room.Left -= $keep }
        $source = [IO.File]::Open($From, 'Open', 'Read', 'ReadWrite')
        try {
            if ($length -gt 5MB) { [void]$source.Seek(-2MB, 'End') }
            $target = $Bundle.Archive.CreateEntry("$($Bundle.Root)/$($Entry -replace '\\', '/')", [IO.Compression.CompressionLevel]::Optimal).Open()
            try { $source.CopyTo($target) } finally { $target.Dispose() }
        } finally { $source.Dispose() }
        $Bundle.Size += $keep
    } catch { $Bundle.Skipped.Add("$Entry`t$($_.Exception.Message)") }
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
