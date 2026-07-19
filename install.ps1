# Claude Code Authentication - Windows Installer
# Usage (PowerShell):
#   irm https://raw.githubusercontent.com/theiconic/ClaudeCodeSetup/main/install.ps1 | iex
#
# Windows counterpart of install-beta.sh: resolves the latest release from
# latest.json, downloads the Windows binaries + package files, and runs the
# per-release ccwb-install.ps1.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$GithubBase   = 'https://raw.githubusercontent.com/theiconic/ClaudeCodeSetup/main/releases'
$LatestJsonUrl = "$GithubBase/latest.json"

function Write-Ok   { param([string]$m) Write-Host "OK $m"   -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "WARN $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "ERROR $m" -ForegroundColor Red }

Write-Host '======================================'
Write-Host 'Claude Code Authentication Installer'
Write-Host '======================================'
Write-Host ''

# ---------------------------------------------------------------------------
# Step 1: Resolve latest release
# ---------------------------------------------------------------------------
Write-Host 'Checking latest release...'
try {
    $latest  = Invoke-RestMethod -Uri $LatestJsonUrl -UseBasicParsing
    $release = $latest.release
    $version = $latest.version
} catch {
    Write-Err "Could not resolve latest release from $LatestJsonUrl : $_"
    exit 1
}

if (-not $release) {
    Write-Err "Could not resolve latest release from $LatestJsonUrl"
    exit 1
}

Write-Host "Release : $release"
Write-Host "Version : $version"
Write-Host ''

$ReleaseBaseUrl = "$GithubBase/$release"

# ---------------------------------------------------------------------------
# Step 2: Install Claude Code CLI if missing
# ---------------------------------------------------------------------------
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host 'Claude Code CLI not found. Installing...'
    $installed = $false
    try {
        irm https://claude.ai/install.ps1 | iex
        if (Get-Command claude -ErrorAction SilentlyContinue) { $installed = $true }
    } catch {
        Write-Warn "Official installer failed: $_"
    }

    if (-not $installed) {
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            Write-Host 'Trying npm...'
            npm install -g @anthropic-ai/claude-code
        } else {
            Write-Err 'Could not install Claude Code automatically. Install it manually from https://claude.ai/download and re-run this installer.'
            exit 1
        }
    }

    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Err 'Claude Code installation failed. Install it manually from https://claude.ai/download and re-run this installer.'
        exit 1
    }
    Write-Ok "Claude Code installed: $(claude --version)"
} else {
    Write-Ok "Claude Code found: $(claude --version)"
}
Write-Host ''

# ---------------------------------------------------------------------------
# Step 3: Download release package (Windows binaries only)
# ---------------------------------------------------------------------------
Write-Host "Downloading installer from release $release..."
$TempDir = Join-Path $env:TEMP "claude-code-install-$([System.IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

$files = @(
    'config.json',
    'claude-settings/settings.json',
    'claude-settings/statusline.ps1',
    'credential-process-windows.exe',
    'otel-helper-windows.exe',
    'quota-poller-windows.exe',
    'ccwb-install.ps1'
)

$total = $files.Count
$count = 0
foreach ($f in $files) {
    $count++
    $dest = Join-Path $TempDir ($f -replace '/', '\')
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Write-Host ("  [{0}/{1}] {2}" -f $count, $total, $f)
    try {
        Invoke-WebRequest -Uri "$ReleaseBaseUrl/$f" -OutFile $dest -UseBasicParsing
    } catch {
        # settings.json / otel-helper are optional; ccwb-install.ps1 tolerates
        # their absence. credential-process + config.json are validated by the
        # per-release installer, so a missing required file fails loudly there.
        Write-Warn "Could not download $f : $_"
    }
}
Write-Ok 'Package downloaded'
Write-Host ''

# ---------------------------------------------------------------------------
# Step 4: Run the per-release installer
# ---------------------------------------------------------------------------
$installer = Join-Path $TempDir 'ccwb-install.ps1'
if (-not (Test-Path $installer)) {
    Write-Err "ccwb-install.ps1 not found in release $release"
    exit 1
}

try {
    Push-Location $TempDir
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer
    $installerExit = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($installerExit -ne 0) {
    Write-Err "Installer exited with code $installerExit"
    exit $installerExit
}

# ---------------------------------------------------------------------------
# Step 5: Test authentication
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '======================================'
Write-Host 'Testing authentication...'
Write-Host '======================================'
$credExe = Join-Path $env:USERPROFILE 'claude-code-with-bedrock\credential-process.exe'
if (Test-Path $credExe) {
    $testOutput = & $credExe --profile theiconic-claude-primary 2>&1 | Out-String
    if ($testOutput -match '"Version"' -and $testOutput -match '"AccessKeyId"') {
        Write-Ok 'Authentication working - credentials obtained successfully'
    } else {
        Write-Warn 'Authentication test failed. Output:'
        Write-Host $testOutput
    }
} else {
    Write-Warn "credential-process.exe not found at $credExe"
}

# ---------------------------------------------------------------------------
# Step 6: Print installed binary versions
# ---------------------------------------------------------------------------
$installDir = Join-Path $env:USERPROFILE 'claude-code-with-bedrock'
Write-Host ''
Write-Host '======================================'
Write-Host 'Installed versions'
Write-Host '======================================'
foreach ($bin in @('quota-poller', 'credential-process', 'otel-helper')) {
    $exe = Join-Path $installDir "$bin.exe"
    if (Test-Path $exe) {
        $v = & $exe --version 2>&1 | Out-String
        Write-Host ("  {0,-20} {1}" -f "${bin}:", $v.Trim())
    } else {
        Write-Host ("  {0,-20} n/a" -f "${bin}:")
    }
}

# Cleanup temp dir
if (Test-Path $TempDir) {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '======================================'
Write-Host 'Installation complete!'
Write-Host '======================================'
