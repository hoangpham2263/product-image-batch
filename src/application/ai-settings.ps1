# Model AI: the model and reasoning level Codex uses for every call (writing reviews and making images), chosen in
# Kiểm tra cấu hình and kept in workspace/ai-model.json. Empty values keep Codex's own default (~/.codex/config.toml).
# A lighter model or a lower reasoning level uses fewer tokens.
$script:AiEfforts = @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')

function Get-AiSettings([string]$ProjectRoot) {
    $path = Join-Path $ProjectRoot 'workspace/ai-model.json'
    $saved = if (Test-Path -LiteralPath $path) { try { Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null } }
    $model = [string]$saved.model; $effort = [string]$saved.effort
    return [pscustomobject]@{
        model = $(if ($model -match '^[\w./:-]{1,80}$') { $model } else { '' })
        effort = $(if ($script:AiEfforts -contains $effort) { $effort } else { '' })
    }
}

function Set-AiSettings([string]$ProjectRoot, [string]$Model, [string]$Effort) {
    if ($Model -and $Model -notmatch '^[\w./:-]{1,80}$') { throw 'Tên model không hợp lệ.' }
    if ($Effort -and $script:AiEfforts -notcontains $Effort) { throw 'Mức suy nghĩ không hợp lệ.' }
    $path = Join-Path $ProjectRoot 'workspace/ai-model.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject ([ordered]@{ model = $Model; effort = $Effort })), [Text.UTF8Encoding]::new($false))
}

# The models Codex offers (codex debug models), in its own order, each with the reasoning levels it supports.
# Without Codex or when the list cannot be read, only the default remains.
function Get-AiModels {
    $codex = @(Get-Command codex -CommandType Application -ErrorAction SilentlyContinue)[0]
    if (-not $codex) { return @() }
    try {
        $catalog = (& $codex.Source debug models 2>$null | Out-String) | ConvertFrom-Json
        return @(foreach ($m in @($catalog.models)) {
                if ($m.visibility -ne 'list' -or [string]$m.slug -notmatch '^[\w./:-]{1,80}$') { continue }
                [pscustomobject]@{ slug = [string]$m.slug; name = [string]$(if ($m.display_name) { $m.display_name } else { $m.slug })
                    efforts = @(@($m.supported_reasoning_levels) | ForEach-Object { [string]$_.effort } | Where-Object { $script:AiEfforts -contains $_ })
                    default_effort = [string]$m.default_reasoning_level }
            })
    } catch { return @() }
}
