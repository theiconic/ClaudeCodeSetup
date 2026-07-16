#!/bin/bash
# Claude Code Authentication - Bootstrap Installer
# Usage: curl -fsSLk https://raw.githubusercontent.com/theiconic/claude-code-with-amazon-bedrock/main/scripts/install/claude-code-install-beta.sh | bash

set -e

GITHUB_BASE="https://raw.githubusercontent.com/theiconic/claude-code-with-amazon-bedrock/refs/heads/beta-ti/assets/releases"
LATEST_JSON_URL="$GITHUB_BASE/latest.json"

echo "======================================"
echo "Claude Code Authentication Installer"
echo "======================================"
echo

# Step 1: Resolve latest release
echo "Checking latest release..."
LATEST_JSON=$(curl -fsSLk "$LATEST_JSON_URL")
RELEASE=$(echo "$LATEST_JSON" | grep -o '"release"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/')
VERSION=$(echo "$LATEST_JSON" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/')

if [ -z "$RELEASE" ]; then
    echo "ERROR: Could not resolve latest release from $LATEST_JSON_URL"
    exit 1
fi

echo "Release : $RELEASE"
echo "Version : $VERSION"
echo

RELEASE_BASE_URL="$GITHUB_BASE/$RELEASE"

# Step 2: Install Claude Code CLI if missing
if ! command -v claude &> /dev/null; then
    echo "Claude Code CLI not found. Installing..."
    set +e
    curl -fsSLk https://claude.ai/install.sh 2>/dev/null | bash </dev/null
    CLAUDE_INSTALL_EXIT=$?
    set -e

    if [ $CLAUDE_INSTALL_EXIT -ne 0 ] || ! command -v claude &> /dev/null; then
        if command -v brew &> /dev/null; then
            echo "Official installer blocked, trying Homebrew..."
            brew install --cask claude-code
        elif command -v npm &> /dev/null; then
            echo "Trying npm..."
            npm install -g @anthropic-ai/claude-code
        else
            echo "ERROR: Could not install Claude Code automatically."
            echo "   Try: brew install --cask claude-code"
            exit 1
        fi
    fi

    if ! command -v claude &> /dev/null; then
        echo "ERROR: Claude Code installation failed. Install manually: brew install --cask claude-code"
        exit 1
    fi
    echo "OK Claude Code installed: $(claude --version)"
else
    echo "OK Claude Code found: $(claude --version)"
fi
echo

# Step 3: Download and run the release install.sh
echo "Downloading installer from release $RELEASE..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Detect platform to only download relevant binaries
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORMS="macos-arm64 macos-intel"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PLATFORMS="linux-arm64 linux-x64"
else
    PLATFORMS="windows"
fi

FILES="config.json claude-settings/settings.json claude-settings/statusline.sh"
for plat in $PLATFORMS; do
    FILES="$FILES credential-process-$plat otel-helper-$plat quota-poller-$plat"
done
# Windows uses .exe suffix
if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
    FILES="config.json claude-settings/settings.json credential-process-windows.exe otel-helper-windows.exe quota-poller-windows.exe"
fi

for f in $FILES; do
    dest="$TMP_DIR/$f"
    mkdir -p "$(dirname "$dest")"
    curl -fsSLk "$RELEASE_BASE_URL/$f" -o "$dest" 2>/dev/null || true
done

# Download and run install.sh from the same release
curl -fsSLk "$RELEASE_BASE_URL/install.sh" -o "$TMP_DIR/install.sh"
chmod +x "$TMP_DIR/install.sh"
echo "OK Package downloaded"
echo

cd "$TMP_DIR"
./install.sh

# Step 4: Test credential-process
echo
echo "======================================"
echo "Testing authentication..."
echo "======================================"
TEST_OUTPUT=$("$HOME/claude-code-with-bedrock/credential-process" --profile theiconic-claude-primary 2>&1)
if echo "$TEST_OUTPUT" | grep -q '"Version"' && echo "$TEST_OUTPUT" | grep -q '"AccessKeyId"'; then
    echo "OK Authentication working — credentials obtained successfully"
else
    echo "WARN Authentication test failed. Output:"
    echo "$TEST_OUTPUT"
fi
