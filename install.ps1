#requires -Version 5.1
# Claude Code Authentication - Windows Installer
# Usage: irm https://raw.githubusercontent.com/theiconic/ClaudeCodeSetup/main/install.ps1 | iex

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$GithubBase = 'https://raw.githubusercontent.com/theiconic/ClaudeCodeSetup/main/releases'
$LatestJsonUrl = "$GithubBase/latest.json"

function Write-Ok { param([string]$Message) Write-Host "OK $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "WARN $Message" -ForegroundColor Yellow }

function Update-SessionPath {
    $paths = @(
        $env:PATH
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::GetEnvironmentVariable('Path', 'User')
        (Join-Path $env:USERPROFILE '.local\bin')
    )
    if ($env:APPDATA) {
        $paths += Join-Path $env:APPDATA 'npm'
    }
    $env:PATH = ($paths | Where-Object { $_ }) -join ';'
}

function Invoke-NativeCommand {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    # Windows PowerShell can turn native stderr into terminating errors.
    # Capture it, then use the process exit code to determine success.
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 1
    $output = & $Command @Arguments 2>&1 | Out-String
    $exitCode = $global:LASTEXITCODE
    [pscustomobject]@{
        Output = $output.Trim()
        ExitCode = $exitCode
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'This installer requires Windows. Use install-beta.sh on macOS or Linux.'
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$TempDir = Join-Path ([IO.Path]::GetTempPath()) "claude-code-install-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $TempDir | Out-Null

try {
    Write-Host '======================================'
    Write-Host 'Claude Code Authentication Installer'
    Write-Host '======================================'
    Write-Host ''

    Write-Host 'Checking latest release...'
    $latest = Invoke-RestMethod -Uri $LatestJsonUrl -UseBasicParsing
    $release = [string]$latest.release
    $version = [string]$latest.version
    if ($release -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or [string]::IsNullOrWhiteSpace($version)) {
        throw "Invalid release metadata from $LatestJsonUrl"
    }
    Write-Host "Release : $release"
    Write-Host "Version : $version"
    Write-Host ''
    $ReleaseBaseUrl = "$GithubBase/$release"

    Update-SessionPath
    if (-not (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Host 'Claude Code CLI not found. Installing...'
        try {
            $claudeInstaller = Join-Path $TempDir 'claude-install.ps1'
            Invoke-WebRequest -Uri 'https://claude.ai/install.ps1' -OutFile $claudeInstaller -UseBasicParsing
            # Isolate installer exit calls from the user's PowerShell session.
            $result = Invoke-NativeCommand -Command $PowerShellExe -Arguments @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $claudeInstaller
            )
            if ($result.Output) { Write-Host $result.Output }
            if ($result.ExitCode -ne 0) {
                Write-Warn "Official installer exited with code $($result.ExitCode)."
            }
        } catch {
            Write-Warn "Official installer failed: $($_.Exception.Message)"
        }

        Update-SessionPath
        if (-not (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue)) {
            $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
            if (-not $npm) {
                throw 'Could not install Claude Code automatically. Install it from https://claude.ai/download and re-run this installer.'
            }
            Write-Host 'Trying npm...'
            $result = Invoke-NativeCommand -Command $npm.Source -Arguments @('install', '-g', '@anthropic-ai/claude-code')
            if ($result.Output) { Write-Host $result.Output }
            if ($result.ExitCode -ne 0) {
                throw "npm installation failed with exit code $($result.ExitCode)."
            }
            Update-SessionPath
        }
    }

    $claude = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue
    if (-not $claude) {
        throw 'Claude Code is not available on PATH after installation. Install it manually and re-run this installer.'
    }
    $result = Invoke-NativeCommand -Command $claude.Source -Arguments @('--version')
    if ($result.ExitCode -ne 0) {
        throw "Claude Code could not start (exit code $($result.ExitCode)): $($result.Output)"
    }
    Write-Ok "Claude Code found: $($result.Output)"
    Write-Host ''

    Write-Host "Downloading installer from release $release..."
    $files = @(
        'config.json'
        'claude-settings/settings.json'
        'claude-settings/statusline.ps1'
        'credential-process-windows.exe'
        'otel-helper-windows.exe'
        'quota-poller-windows.exe'
        'ccwb-install.ps1'
    )
    $count = 0
    foreach ($file in $files) {
        $count++
        Write-Host ("  [{0}/{1}] {2}" -f $count, $files.Count, $file)
        $destination = Join-Path $TempDir $file
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        try {
            Invoke-WebRequest -Uri "$ReleaseBaseUrl/$file" -OutFile $destination -UseBasicParsing
        } catch {
            throw "Could not download required release file '$file': $($_.Exception.Message)"
        }
        if ((Get-Item -LiteralPath $destination).Length -eq 0) {
            throw "Downloaded release file '$file' is empty."
        }
    }
    Write-Ok 'Package downloaded'
    Write-Host ''

    Push-Location $TempDir
    try {
        & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $TempDir 'ccwb-install.ps1')
        $installerExit = $LASTEXITCODE
        if ($installerExit -ne 0) {
            throw "Release installer exited with code $installerExit."
        }
    } finally {
        Pop-Location
    }

    $installDir = Join-Path $env:USERPROFILE 'claude-code-with-bedrock'
    $credExe = Join-Path $installDir 'credential-process.exe'
    if (-not (Test-Path -LiteralPath $credExe -PathType Leaf)) {
        throw "Release installer completed, but credential-process.exe was not found at $credExe."
    }

    Write-Host ''
    Write-Host '======================================'
    Write-Host 'Testing authentication...'
    Write-Host '======================================'
    $result = Invoke-NativeCommand -Command $credExe -Arguments @('--profile', 'theiconic-claude-primary')
    $authenticated = $false
    if ($result.ExitCode -eq 0) {
        try {
            $credentials = $result.Output | ConvertFrom-Json
            $authenticated = $credentials.Version -eq 1 -and -not [string]::IsNullOrWhiteSpace($credentials.AccessKeyId)
        } catch {
            Write-Warn 'Authentication returned an invalid credential response.'
        }
    }
    if ($authenticated) {
        Write-Ok 'Authentication working - credentials obtained successfully'
    } else {
        # Never echo credential-process output: it may contain AWS secrets.
        Write-Warn "Authentication test failed (exit code $($result.ExitCode)). Check your sign-in and profile configuration."
    }

    Write-Host ''
    Write-Host '======================================'
    Write-Host 'Installed versions'
    Write-Host '======================================'
    foreach ($binary in @('quota-poller', 'credential-process', 'otel-helper')) {
        $exe = Join-Path $installDir "$binary.exe"
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
            Write-Warn "$binary was not found at $exe."
            continue
        }
        $result = Invoke-NativeCommand -Command $exe -Arguments @('--version')
        if ($result.ExitCode -ne 0) {
            Write-Warn "$binary --version failed (exit code $($result.ExitCode))."
            continue
        }
        Write-Host ("  {0,-20} {1}" -f "${binary}:", $result.Output)
    }

    Write-Host ''
    Write-Host '======================================'
    if ($authenticated) {
        Write-Host 'Installation complete!'
    } else {
        Write-Warn 'Installation complete, but authentication needs attention.'
    }
    Write-Host '======================================'
} finally {
    try {
        Remove-Item -LiteralPath $TempDir -Recurse -Force
    } catch {
        Write-Warn "Could not remove temporary directory '$TempDir': $($_.Exception.Message)"
    }
}
