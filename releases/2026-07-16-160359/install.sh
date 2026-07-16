#!/bin/bash
# Claude Code Authentication Installer (generic)

set -e

echo "======================================"
echo "Claude Code Authentication Installer"
echo "======================================"
echo

# ---------------------------------------------------------------------------
# Bootstrap: if run via curl | bash, download the full release package first
# ---------------------------------------------------------------------------
RELEASE_BASE_URL="https://raw.githubusercontent.com/theiconic/ClaudeCodeSetup/main/releases/2026-07-16-160359"
if [ ! -f "config.json" ] && [ -n "$RELEASE_BASE_URL" ]; then
    echo "Downloading release package..."
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    for f in config.json \
              credential-process-macos-arm64 credential-process-macos-intel \
              credential-process-windows.exe \
              otel-helper-macos-arm64 otel-helper-macos-intel otel-helper-windows.exe \
              quota-poller-macos-arm64 quota-poller-macos-intel quota-poller-windows.exe \
              "claude-settings/settings.json" "claude-settings/statusline.sh"; do
        dest="$TMP_DIR/$f"
        mkdir -p "$(dirname "$dest")"
        curl -fsSLk "$RELEASE_BASE_URL/$f" -o "$dest" || true
    done
    cd "$TMP_DIR"
    echo "OK Package downloaded"
fi

# Check prerequisites
echo "Checking prerequisites..."
HAS_ERRORS=false

if [ ! -f "config.json" ]; then
    echo "ERROR: config.json not found in current directory"
    echo "       Make sure you are running this from the extracted package folder"
    HAS_ERRORS=true
fi

PYTHON=""
if command -v python3 &> /dev/null; then
    PYTHON="python3"
elif command -v python &> /dev/null; then
    PYTHON="python"
else
    echo "ERROR: Python is not installed (python3 or python)"
    echo "       Python is needed to parse configuration files"
    HAS_ERRORS=true
fi

if [ "$HAS_ERRORS" = "true" ]; then
    exit 1
fi


if [ ! -f "claude-settings/settings.json" ]; then
    echo "WARNING: claude-settings/settings.json not found"
    echo "         Claude Code IDE settings will not be configured automatically"
    echo ""
fi

echo "OK Prerequisites validated"

# Detect platform and architecture
echo
echo "Detecting platform and architecture..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macos"
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        echo "Detected macOS ARM64 (Apple Silicon)"
        BINARY_SUFFIX="macos-arm64"
    else
        echo "Detected macOS Intel"
        BINARY_SUFFIX="macos-intel"
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PLATFORM="linux"
    ARCH=$(uname -m)
    if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
        echo "Detected Linux ARM64"
        BINARY_SUFFIX="linux-arm64"
    else
        echo "Detected Linux x64"
        BINARY_SUFFIX="linux-x64"
    fi
else
    echo "Unsupported platform: $OSTYPE"
    echo "   This installer supports macOS and Linux only."
    exit 1
fi

CREDENTIAL_BINARY="credential-process-$BINARY_SUFFIX"
OTEL_BINARY="otel-helper-$BINARY_SUFFIX"
QUOTA_POLLER_BINARY="quota-poller-$BINARY_SUFFIX"

if [ ! -f "$CREDENTIAL_BINARY" ]; then
    echo "Binary not found for your platform: $CREDENTIAL_BINARY"
    echo "   Please ensure you have the correct package for your architecture."
    exit 1
fi

# Create directory
echo
echo "Installing authentication tools..."
mkdir -p ~/claude-code-with-bedrock

cp "$CREDENTIAL_BINARY" ~/claude-code-with-bedrock/credential-process
cp config.json ~/claude-code-with-bedrock/
chmod +x ~/claude-code-with-bedrock/credential-process

if [[ "$OSTYPE" == "darwin"* ]]; then
    # Remove quarantine flag added by macOS when downloading unsigned binaries.
    # Without this, Gatekeeper blocks execution with "Apple could not verify..." dialog.
    xattr -d com.apple.quarantine ~/claude-code-with-bedrock/credential-process 2>/dev/null || true
    xattr -d com.apple.quarantine ~/claude-code-with-bedrock/quota-poller 2>/dev/null || true
    xattr -d com.apple.quarantine ~/claude-code-with-bedrock/otel-helper 2>/dev/null || true
    echo
    echo "⚠️  macOS Keychain Access:"
    echo "   On first use, macOS will ask for permission to access the keychain."
    echo "   This is normal and required for secure credential storage."
    echo "   Click 'Always Allow' when prompted."
fi

# Copy Claude Code settings if present
if [ -d "claude-settings" ]; then
    echo
    echo "Installing Claude Code settings..."
    mkdir -p ~/.claude

    if [ -f "claude-settings/settings.json" ]; then
        if [ -f ~/.claude/settings.json ]; then
            echo "Existing Claude Code settings found"
            BACKUP_NAME="settings.json.backup-$(date +%Y%m%d-%H%M%S)"
            cp ~/.claude/settings.json ~/.claude/$BACKUP_NAME
            echo "  Backed up to: ~/.claude/$BACKUP_NAME"
            if [ -t 0 ]; then
                read -p "Overwrite with new settings? (Y/n): " -n 1 -r
                echo
                if [[ -z "$REPLY" ]]; then
                    REPLY="y"
                fi
            else
                echo "Non-interactive install — overwriting settings automatically."
                REPLY="y"
            fi
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Skipping Claude Code settings..."
                SKIP_SETTINGS=true
            fi
        fi

        if [ "$SKIP_SETTINGS" != "true" ]; then
            # Install statusline script — ask if one already exists
            if [ -f "claude-settings/statusline.sh" ]; then
                if [ -f ~/.claude/statusline.sh ]; then
                    echo
                    echo "A statusline script already exists at ~/.claude/statusline.sh"
                    if [ -t 0 ]; then
                        read -p "Override with the quota-aware statusline? (y/N): " -n 1 -r
                        echo
                    else
                        echo "Non-interactive install — overwriting statusline automatically."
                        REPLY="y"
                    fi
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        cp claude-settings/statusline.sh ~/.claude/statusline.sh
                        chmod +x ~/.claude/statusline.sh
                        echo "OK Statusline script installed: ~/.claude/statusline.sh"
                    else
                        echo "Keeping your existing statusline."
                        echo "NOTE: A quota-aware statusline is available in claude-settings/statusline.sh"
                        echo "      It shows daily/monthly token usage in your Claude Code status bar."
                        echo "      You can merge it manually or replace it later by re-running this installer."
                    fi
                else
                    cp claude-settings/statusline.sh ~/.claude/statusline.sh
                    chmod +x ~/.claude/statusline.sh
                    echo "OK Statusline script installed: ~/.claude/statusline.sh"
                fi
            fi

            sed -e "s|__OTEL_HELPER_PATH__|$HOME/claude-code-with-bedrock/otel-helper|g" \
                -e "s|__CREDENTIAL_PROCESS_PATH__|$HOME/claude-code-with-bedrock/credential-process|g" \
                -e "s|\"__STATUSLINE_PATH__\"|{\"type\":\"command\",\"command\":\"$HOME/.claude/statusline.sh\"}|g" \
                "claude-settings/settings.json" > ~/.claude/settings.json

            if grep -q '__CREDENTIAL_PROCESS_PATH__\|__OTEL_HELPER_PATH__\|__STATUSLINE_PATH__' ~/.claude/settings.json 2>/dev/null; then
                echo "WARNING: Some path placeholders were not replaced in settings.json"
                echo "         You may need to edit the file manually: ~/.claude/settings.json"
            else
                echo "OK Claude Code settings configured: ~/.claude/settings.json"
            fi
        fi
    fi
fi

# Install quota poller (triggered automatically by the statusline when cache is stale)
if [ -f "$QUOTA_POLLER_BINARY" ]; then
    echo
    echo "Installing quota poller..."
    cp "$QUOTA_POLLER_BINARY" ~/claude-code-with-bedrock/quota-poller
    chmod +x ~/claude-code-with-bedrock/quota-poller
    echo "OK quota-poller installed: ~/claude-code-with-bedrock/quota-poller"
fi

# Copy OTEL helper executable if present
if [ -f "$OTEL_BINARY" ]; then
    echo
    echo "Installing OTEL helper..."
    cp "$OTEL_BINARY" ~/claude-code-with-bedrock/otel-helper
    chmod +x ~/claude-code-with-bedrock/otel-helper
    echo "OTEL helper installed"
fi

# Update AWS config
echo
echo "Configuring AWS profiles..."
mkdir -p ~/.aws

PROFILES=$($PYTHON -c "import json; profiles = list(json.load(open('config.json')).keys()); print(' '.join(profiles))")

if [ -z "$PROFILES" ]; then
    echo "No profiles found in config.json"
    exit 1
fi

echo "Found profiles: $PROFILES"
echo

# Read default region from config.json (first profile's aws_region)
DEFAULT_REGION=$($PYTHON -c "
import json
c = json.load(open('config.json'))
p = list(c.keys())[0]
print(c[p].get('aws_region', 'us-east-1'))
")

for PROFILE_NAME in $PROFILES; do
    echo "Configuring AWS profile: $PROFILE_NAME"

    sed -i.bak "/\[profile $PROFILE_NAME\]/,/^$/d" ~/.aws/config 2>/dev/null || true

    PROFILE_REGION=$($PYTHON -c "
import json
print(json.load(open('config.json')).get('$PROFILE_NAME', {}).get('aws_region', '$DEFAULT_REGION'))
")

    cat >> ~/.aws/config << EOF
[profile $PROFILE_NAME]
credential_process = $HOME/claude-code-with-bedrock/credential-process --profile $PROFILE_NAME
region = $PROFILE_REGION
EOF
    echo "  Created AWS profile '$PROFILE_NAME'"
done

# Per-zone isolation: print per-zone inference-profile ARNs the user
# must configure in Claude Code. No shell function is installed — IAM
# enforces zone isolation on its own, and the shell-function approach
# was too fragile across IDE integrations, non-interactive shells,
# cron, SSH, container exec, and multiple-shell user setups. Users
# configure ANTHROPIC_MODEL explicitly, once, in whichever mechanism
# fits their workflow.
FIRST_PROFILE=$(echo $PROFILES | awk '{print $1}')
ISOLATION_ON=$($PYTHON -c "
import json
c = json.load(open('config.json')).get('$FIRST_PROFILE', {})
print('yes' if c.get('enforce_project_isolation') else 'no')
")
if [ "$ISOLATION_ON" = "yes" ]; then
    # Remove any wrapper artifacts left over from previous installs
    # that shipped the shell-function approach. Safe no-op if absent.
    rm -f "$HOME/claude-code-with-bedrock/claude-wrapper.sh" 2>/dev/null
    for rc in ~/.zshrc ~/.bashrc; do
        [ -f "$rc" ] || continue
        if grep -q "ccwb claude wrapper" "$rc" 2>/dev/null; then
            # Strip the marker block in place.
            $PYTHON - "$rc" <<'STRIPPY'
import re, sys
p = sys.argv[1]
with open(p) as f:
    text = f.read()
pattern = re.compile(r'\n*# >>> ccwb claude wrapper >>>.*?# <<< ccwb claude wrapper <<<\n*', re.S)
new = pattern.sub('\n', text).rstrip() + '\n'
with open(p, 'w') as f:
    f.write(new)
STRIPPY
            echo "  Removed legacy ccwb claude wrapper block from $rc"
        fi
    done

    echo
    echo "=========================================================================="
    echo "Next step: configure your model + region"
    echo "=========================================================================="
    echo
    echo "Before running 'claude', set BOTH the model ARN and the AWS region"
    echo "that matches it (your admin will give you both):"
    echo
    echo "    export AWS_REGION='<region provided by your team>'     # e.g. eu-west-3"
    echo "    export ANTHROPIC_MODEL='<arn provided by your team>'"
    echo
    echo "Add those two lines to ~/.bashrc or ~/.zshrc to persist."
    echo
    echo "Both must be set together — the ARN and the region are paired."
    echo "If only ANTHROPIC_MODEL is set, the AWS SDK defaults to a different"
    echo "region and rejects the call with 'invalid ARN'."
    echo "=========================================================================="
fi

# Post-install validation
echo
echo "Validating installation..."
if [ -f ~/claude-code-with-bedrock/credential-process ]; then
    echo "  OK credential-process: ~/claude-code-with-bedrock/credential-process"
else
    echo "  FAIL credential-process not found at: ~/claude-code-with-bedrock/credential-process"
fi
if [ -f ~/.claude/settings.json ]; then
    echo "  OK settings.json: ~/.claude/settings.json"
else
    echo "  WARN settings.json not found at: ~/.claude/settings.json"
fi

echo
echo "======================================"
echo "Installation complete!"
echo "======================================"
echo
echo "Available profiles:"
for PROFILE_NAME in $PROFILES; do
    echo "  - $PROFILE_NAME"
done
echo
echo "To use Claude Code authentication:"
echo "  export AWS_PROFILE=<profile-name>"
echo "  aws sts get-caller-identity"
echo
FIRST_PROFILE=$(echo $PROFILES | awk '{print $1}')
echo "Example:"
echo "  export AWS_PROFILE=$FIRST_PROFILE"
echo "  aws sts get-caller-identity"
echo
echo "Note: Authentication will automatically open your browser when needed."
echo
