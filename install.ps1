# Claude Code Windows Installer
# Usage (PowerShell, run as normal user):
#   irm https://raw.githubusercontent.com/theiconic/claude-code-with-amazon-bedrock/main/scripts/install/claude-code-install.ps1 | iex

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── helpers ────────────────────────────────────────────────────────────────────
function Write-Step { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$msg) Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Fail { param([string]$msg) Write-Host "    ERR $msg" -ForegroundColor Red; exit 1 }

# ── config ─────────────────────────────────────────────────────────────────────
$PackageUrl  = "https://claude-code-auth-distribution-417652811636.s3.amazonaws.com/packages/20260527-083348/claude-code-package-20260527-083348.zip"
$ZipName     = "claude-code-package-20260527-083348.zip"
$ExtractDir  = "claude-code-package"
$TempDir     = Join-Path $env:TEMP "claude-code-install-$([System.IO.Path]::GetRandomFileName())"

# ── main ───────────────────────────────────────────────────────────────────────
try {
    Write-Host ""
    Write-Host "  Claude Code Installer for Windows" -ForegroundColor Yellow
    Write-Host "  ===================================" -ForegroundColor Yellow

    # Step 1 — Download
    Write-Step "Step 1 — Downloading package..."
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    $ZipPath = Join-Path $TempDir $ZipName

    try {
        Invoke-WebRequest -Uri $PackageUrl -OutFile $ZipPath -UseBasicParsing
        Write-Ok "Downloaded to $ZipPath"
    } catch {
        Write-Fail "Download failed: $_"
    }

    # Step 2 — Extract
    Write-Step "Step 2 — Extracting package..."
    $ExtractPath = Join-Path $TempDir $ExtractDir
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force
    Write-Ok "Extracted to $ExtractPath"

    # Step 3 — Install
    Write-Step "Step 3 — Running installer..."

    # Find install.bat (handles nested zip structures)
    $InstallBat = Get-ChildItem -Path $ExtractPath -Filter "install.bat" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $InstallBat) {
        Write-Fail "install.bat not found in extracted package."
    }

    Push-Location $InstallBat.DirectoryName
    try {
        cmd /c "install.bat"
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "install.bat exited with code $LASTEXITCODE"
        }
        Write-Ok "Installer completed successfully"
    } finally {
        Pop-Location
    }

    # Step 4 — Done
    Write-Host ""
    Write-Host "  Installation complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  To start Claude Code, open a new terminal and run:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host '      $env:AWS_PROFILE = "theiconic-claude-primary"' -ForegroundColor White
    Write-Host "      claude" -ForegroundColor White
    Write-Host ""
    Write-Host "  Or in Command Prompt:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host '      set AWS_PROFILE=theiconic-claude-primary' -ForegroundColor White
    Write-Host "      claude" -ForegroundColor White
    Write-Host ""
    Write-Host "  On first run, your browser will open and prompt you to log in with Okta." -ForegroundColor Yellow
    Write-Host ""

} finally {
    # Cleanup temp dir
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
