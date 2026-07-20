# Claude Code Native Statusline (Windows / PowerShell)
# Receives JSON context from Claude Code via stdin.
# PowerShell port of statusline.sh — same layout: path/git, context bar, model,
# duration, daily/monthly quota bars, and cost (from quota-poller.exe cache).

$ErrorActionPreference = 'SilentlyContinue'

# Force UTF-8 in/out so emoji + ANSI render correctly. PowerShell defaults to
# UTF-16 on the console, which garbles the status line and mangles the JSON
# arriving on stdin.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
} catch {}

# ---------------------------------------------------------------------------
# Read stdin JSON
# ---------------------------------------------------------------------------
$raw = [Console]::In.ReadToEnd()
try { $ctx = $raw | ConvertFrom-Json } catch { $ctx = $null }

function Get-Prop {
    param($obj, [string[]]$path)
    foreach ($p in $path) {
        if ($null -eq $obj) { return $null }
        $obj = $obj.$p
    }
    return $obj
}

# ---------------------------------------------------------------------------
# Parse fields (tolerant of both new + legacy shapes)
# ---------------------------------------------------------------------------
$cwd = Get-Prop $ctx @('workspace','current_dir')
if (-not $cwd) { $cwd = Get-Prop $ctx @('cwd') }
if (-not $cwd) { $cwd = (Get-Location).Path }

$gitNumFiles = Get-Prop $ctx @('workspace','gitNumStagedOrUnstagedFilesChanged')
if (-not $gitNumFiles) { $gitNumFiles = Get-Prop $ctx @('gitNumStagedOrUnstagedFilesChanged') }
if (-not $gitNumFiles) { $gitNumFiles = 0 }

$model = Get-Prop $ctx @('model','display_name')
if (-not $model) { $model = 'unknown' }
$modelId = Get-Prop $ctx @('model','id')
if (-not $modelId) { $modelId = Get-Prop $ctx @('model_id') }

$ctxPct = Get-Prop $ctx @('context_window','used_percentage')
if ($null -eq $ctxPct) { $ctxPct = Get-Prop $ctx @('used_percentage') }
if ($null -eq $ctxPct) { $ctxPct = 0 }
$ctxPct = [int][math]::Floor([double]$ctxPct)

$maxTokens = Get-Prop $ctx @('context_window','context_window_size')
if (-not $maxTokens) { $maxTokens = Get-Prop $ctx @('context_window_size') }
if (-not $maxTokens) {
    if ("$model $modelId" -match '1m|1000k') { $maxTokens = 1000000 } else { $maxTokens = 200000 }
}
$conversationTokens = [long][math]::Floor($maxTokens * $ctxPct / 100)

$durationMs = Get-Prop $ctx @('cost','total_duration_ms')
if (-not $durationMs) { $durationMs = Get-Prop $ctx @('total_duration_ms') }
if (-not $durationMs) { $durationMs = 0 }

$linesAdded = Get-Prop $ctx @('cost','total_lines_added')
if (-not $linesAdded) { $linesAdded = Get-Prop $ctx @('total_lines_added') }
if (-not $linesAdded) { $linesAdded = 0 }
$linesRemoved = Get-Prop $ctx @('cost','total_lines_removed')
if (-not $linesRemoved) { $linesRemoved = Get-Prop $ctx @('total_lines_removed') }
if (-not $linesRemoved) { $linesRemoved = 0 }

# ---------------------------------------------------------------------------
# Colors (ANSI — Windows Terminal / modern conhost support these)
# ---------------------------------------------------------------------------
$e = [char]27
$W = "$e[97m"; $G = "$e[32m"; $R = "$e[31m"; $Y = "$e[33m"; $C = "$e[36m"; $DM = "$e[90m"; $D = "$e[0m"

# Emoji + glyphs. Use ConvertFromUtf32 because [char] only holds 16-bit BMP
# values — the astral-plane emoji (U+1F4xx) would otherwise be truncated/wrong.
$EM_FOLDER = [char]::ConvertFromUtf32(0x1F4C2)  # folder
$EM_CHART  = [char]::ConvertFromUtf32(0x1F4CA)  # bar chart
$EM_ROBOT  = [char]::ConvertFromUtf32(0x1F916)  # robot
$EM_TIMER  = [char]::ConvertFromUtf32(0x23F1)   # stopwatch (BMP, but keep uniform)
$EM_TREND  = [char]::ConvertFromUtf32(0x1F4C8)  # chart up
$EM_MONEY  = [char]::ConvertFromUtf32(0x1F4B0)  # money bag
$EM_WARN   = [char]::ConvertFromUtf32(0x26A0)   # warning (BMP)
$GL_FULL   = [char]::ConvertFromUtf32(0x2588)   # full block
$GL_LIGHT  = [char]::ConvertFromUtf32(0x2591)   # light shade

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Format-Model {
    param([string]$m)
    if ($m -match '(?i)(opus|sonnet|haiku)\s*[0-9]') {
        $tier = ([regex]::Match($m, '(?i)(opus|sonnet|haiku)').Value)
        $ver  = ([regex]::Match($m, '[0-9]+\.[0-9]+').Value)
        $tier = $tier.Substring(0,1).ToUpper() + $tier.Substring(1).ToLower()
        if ($ver) { return "$tier-$ver" } else { return $tier }
    }
    if ($m -match '(?i)claude.*(opus|sonnet|haiku)') {
        $tier = ([regex]::Match($m, '(?i)(opus|sonnet|haiku)').Value)
        $tier = $tier.Substring(0,1).ToUpper() + $tier.Substring(1).ToLower()
        $vm = [regex]::Matches($m, '[0-9]+[.\-][0-9]+')
        $ver = if ($vm.Count -gt 0) { $vm[$vm.Count-1].Value -replace '-', '.' } else { '' }
        if ($ver) { return "$tier-$ver" } else { return $tier }
    }
    return ($m -replace '^claude-', '').Substring(0, [math]::Min(14, ($m -replace '^claude-','').Length))
}

function Shorten-Path {
    param([string]$p)
    $home = $env:USERPROFILE
    if ($home -and $p.StartsWith($home)) { $p = '~' + $p.Substring($home.Length) }
    if ($p.Length -gt 40) {
        $parts = $p -split '[\\/]'
        if ($parts.Count -ge 2) { $p = $parts[$parts.Count-2] + '/' + $parts[$parts.Count-1] }
    }
    return $p
}

function Progress-Bar {
    param([int]$pct)
    $width = 10
    # Floor (not round) to match bash integer division: filled=$((pct*width/100)).
    $filled = [int][math]::Floor($pct * $width / 100)
    if ($filled -gt $width) { $filled = $width }
    if ($filled -lt 0) { $filled = 0 }
    $empty = $width - $filled
    if ($pct -ge 90) { $color = $R } elseif ($pct -ge 70) { $color = $Y } else { $color = $G }
    $bar = ''
    for ($i=0; $i -lt $filled; $i++) { $bar += "$color" + $GL_FULL + $D }
    for ($i=0; $i -lt $empty;  $i++) { $bar += "$DM" + $GL_LIGHT + $D }
    return $bar
}

function Format-Tokens {
    param([long]$n)
    # Floor to match bash integer division (e.g. 593.9M → 593M, not 594M).
    if ($n -ge 1000000000) { return "$([long][math]::Floor($n/1000000000))B" }
    if ($n -ge 1000000)    { return "$([long][math]::Floor($n/1000000))M" }
    if ($n -ge 1000)       { return "$([long][math]::Floor($n/1000))k" }
    return "$n"
}

function Format-Duration {
    param([long]$ms)
    $secs = [int]($ms / 1000)
    $mins = [int]($secs / 60)
    $secs = $secs % 60
    if ($mins -gt 0) { return "${mins}m ${secs}s" } else { return "${secs}s" }
}

# ---------------------------------------------------------------------------
# Git branch (cached 5 min)
# ---------------------------------------------------------------------------
$gitBranch = ''
if ($cwd -and (Test-Path $cwd) -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $cacheDir = Join-Path $env:TEMP 'claude-statusline'
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    $hash = [System.BitConverter]::ToString(
        [System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($cwd))
    ).Replace('-','')
    $cacheFile = Join-Path $cacheDir "git_branch_$hash"
    if ((Test-Path $cacheFile) -and ((Get-Date) - (Get-Item $cacheFile).LastWriteTime).TotalSeconds -lt 300) {
        $gitBranch = (Get-Content $cacheFile -Raw).Trim()
    } else {
        $gitBranch = (& git -C $cwd branch --show-current 2>$null | Out-String).Trim()
        if ($gitBranch) { Set-Content -Path $cacheFile -Value $gitBranch }
    }
}

# ---------------------------------------------------------------------------
# Line 1: path  git branch  lines diff
# ---------------------------------------------------------------------------
$shortCwd = Shorten-Path $cwd
$line1 = $EM_FOLDER + " ${W}${shortCwd}${D}"
if ($gitBranch) {
    $line1 += "   ${G}${gitBranch}${D}"
    if ([int]$gitNumFiles -gt 0) { $line1 += " ${DM}(${gitNumFiles})${D}" }
}
if ([int]$linesAdded -gt 0 -or [int]$linesRemoved -gt 0) {
    $line1 += "  ${G}+${linesAdded}${D} ${R}-${linesRemoved}${D}"
}

# ---------------------------------------------------------------------------
# Line 2: context bar  model  duration  quota  cost
# ---------------------------------------------------------------------------
$ctxBar  = Progress-Bar $ctxPct
$ctxUsed = Format-Tokens $conversationTokens
$ctxMax  = Format-Tokens $maxTokens
$line2 = $EM_CHART + " ${W}${ctxUsed}/${ctxMax}${D} $ctxBar ${W}${ctxPct}%${D}"
$line2 += " ${DM}|${D} " + $EM_ROBOT + " ${W}$(Format-Model $model)${D}"
if ([long]$durationMs -gt 0) {
    $line2 += " ${DM}|${D} " + $EM_TIMER + " ${DM}$(Format-Duration $durationMs)${D}"
}

# ---------------------------------------------------------------------------
# Quota + cost from quota-poller cache
# ---------------------------------------------------------------------------
$installConfig = Join-Path $env:USERPROFILE 'claude-code-with-bedrock\config.json'
$activeProfile = ''
$costEnabled = $false
if (Test-Path $installConfig) {
    try {
        $cfg = Get-Content $installConfig -Raw | ConvertFrom-Json
        $activeProfile = ($cfg.PSObject.Properties.Name | Select-Object -First 1)
        # Cost display is opt-in via "statusline_cost_enable": true in the
        # active profile. Default off: skip both the CloudWatch refresh and the
        # money line so cost never appears (and we never hit CloudWatch unasked).
        if ($activeProfile -and $cfg.$activeProfile.statusline_cost_enable -eq $true) {
            $costEnabled = $true
        }
    } catch {}
}

$sessionDir = Join-Path $env:USERPROFILE '.claude-code-session'
$quotaCache = if ($activeProfile) { Join-Path $sessionDir "$activeProfile-quota-cache.json" } else { '' }
$costCache  = if ($activeProfile) { Join-Path $sessionDir "$activeProfile-cost-cache.json" }  else { '' }
$poller     = Join-Path $env:USERPROFILE 'claude-code-with-bedrock\quota-poller.exe'

# Refresh quota cache in background if stale (>5 min)
if ((Test-Path $poller) -and $activeProfile) {
    $age = 999999
    if (Test-Path $quotaCache) { $age = ((Get-Date) - (Get-Item $quotaCache).LastWriteTime).TotalSeconds }
    if ($age -gt 300) {
        Start-Process -FilePath $poller -ArgumentList "--profile","$activeProfile","--interval","0" -WindowStyle Hidden | Out-Null
    }
}

# Refresh cost cache in background every 15 min (only when cost is enabled)
if ($costEnabled -and (Test-Path $poller) -and $activeProfile) {
    $age = 999999
    if (Test-Path $costCache) { $age = ((Get-Date) - (Get-Item $costCache).LastWriteTime).TotalSeconds }
    if ($age -gt 900) {
        $tmp = "$costCache.tmp"
        Start-Process -FilePath $poller `
            -ArgumentList "--profile","$activeProfile","--statusline","--include-cost" `
            -RedirectStandardOutput $tmp -WindowStyle Hidden -PassThru | Out-Null
        # Note: rename happens on next render once the tmp file is complete.
    }
}
# Promote a completed cost tmp file (written by a prior background run)
if ($costEnabled -and $costCache -and (Test-Path "$costCache.tmp")) {
    try {
        $t = Get-Content "$costCache.tmp" -Raw | ConvertFrom-Json  # validate JSON
        if ($t) { Move-Item -Force "$costCache.tmp" $costCache }
    } catch {}
}

$inv = [System.Globalization.CultureInfo]::InvariantCulture
$alertLevel = ''; $alertMessage = ''
if ($quotaCache -and (Test-Path $quotaCache)) {
    try { $q = Get-Content $quotaCache -Raw | ConvertFrom-Json } catch { $q = $null }
    if ($q) {
        $dPct = [double]$q.daily_percent
        $mPct = [double]$q.monthly_percent
        # Percent strings: invariant culture so a comma-decimal locale doesn't
        # print "3,6%". Matches bash which echoes the raw JSON number verbatim.
        $dPctStr = $dPct.ToString($inv)
        $mPctStr = $mPct.ToString($inv)
        # Color/bar thresholds: round (matches bash printf '%.0f').
        $dInt = [int][math]::Round($dPct)
        $mInt = [int][math]::Round($mPct)
        if ($dInt -ge 90) { $dColor = $R } elseif ($dInt -ge 80) { $dColor = $Y } else { $dColor = $G }
        if ($mInt -ge 90) { $mColor = $R } elseif ($mInt -ge 80) { $mColor = $Y } else { $mColor = $G }
        $dBar = Progress-Bar $dInt
        $mBar = Progress-Bar $mInt
        $dTok = Format-Tokens ([long]$q.daily_tokens);   $dLim = Format-Tokens ([long]$q.daily_limit)
        $mTok = Format-Tokens ([long]$q.monthly_tokens); $mLim = Format-Tokens ([long]$q.monthly_limit)

        $line2 += " ${DM}|${D} " + $EM_TREND + " D: ${dColor}${dPctStr}%${D} $dBar ${DM}${dTok}/${dLim}${D}"
        $line2 += "  ${DM}|${D}  M: ${mColor}${mPctStr}%${D} $mBar ${DM}${mTok}/${mLim}${D}"

        # Cost from cached --include-cost output (opt-in via statusline_cost_enable)
        if ($costEnabled -and $costCache -and (Test-Path $costCache)) {
            try { $cc = Get-Content $costCache -Raw | ConvertFrom-Json } catch { $cc = $null }
            $today = Get-Prop $cc @('cost','today_usd')
            $month = Get-Prop $cc @('cost','month_usd')
            if ($today -and $month) {
                # InvariantCulture + "F2" → always a dot decimal, no thousands
                # separators (matches the bash printf '%.2f'). Plain {0:N2} would
                # emit commas on comma-decimal Windows locales.
                $tDisp = ([double]$today).ToString('F2', $inv)
                $mDisp = ([double]$month).ToString('F2', $inv)
                $line2 += "  ${DM}|${D} " + $EM_MONEY + " ${G}`$${tDisp}${DM}/day  `$${mDisp}${DM}/mo${D}"
            }
        }

        $alertLevel   = $q.alert_level
        $alertMessage = $q.alert_message
    }
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
[Console]::Out.Write($line1 + "`n")
[Console]::Out.Write($line2 + "`n")
if ($alertMessage) {
    if ($alertLevel -eq 'blocked') { $ac = "$e[1;31m" } else { $ac = "$e[1;33m" }
    [Console]::Out.Write($ac + $EM_WARN + "  " + $alertMessage + "$e[0m`n")
}
