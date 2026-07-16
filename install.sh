#!/bin/bash
# Claude Code Authentication - Bootstrap Installer
# Usage: curl -fsSLk https://raw.githubusercontent.com/theiconic/claude-code-with-amazon-bedrock/main/scripts/install/claude-code-install.sh | bash

set -e

PACKAGE_URL="https://claude-code-auth-distribution-417652811636.s3.amazonaws.com/packages/20260527-083348/claude-code-package-20260527-083348.zip"
PACKAGE_FILE="claude-code-package.zip"
PACKAGE_DIR="claude-code-package"

# Extract version from URL
VERSION=$(echo "$PACKAGE_URL" | grep -oE '[0-9]{8}-[0-9]{6}' | head -1)

echo "======================================"
echo "Claude Code Authentication Installer"
echo "Version: $VERSION"
echo "======================================"
echo

# Remove macOS quarantine flag from a binary/app to avoid Privacy & Security prompt
_unquarantine() {
    local target="$1"
    if [[ "$OSTYPE" == "darwin"* ]] && [ -e "$target" ]; then
        xattr -d com.apple.quarantine "$target" 2>/dev/null || true
        xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
    fi
}

# Step 0a: Check if AWS CLI is installed, install if missing
if ! command -v aws &> /dev/null; then
    echo "AWS CLI not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install awscli
        else
            curl -fsSLk "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
            sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
            rm -f /tmp/AWSCLIV2.pkg
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        ARCH=$(uname -m)
        if [[ "$ARCH" == "aarch64" ]]; then
            curl -fsSLk "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o /tmp/awscliv2.zip
        else
            curl -fsSLk "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
        fi
        unzip -qo /tmp/awscliv2.zip -d /tmp/awscli-install
        sudo /tmp/awscli-install/aws/install
        rm -rf /tmp/awscliv2.zip /tmp/awscli-install
    fi
    if ! command -v aws &> /dev/null; then
        echo "⚠️  AWS CLI installation failed. Please install manually: https://aws.amazon.com/cli/"
        exit 1
    fi
    echo "✓ AWS CLI installed: $(aws --version)"
    echo
else
    echo "✓ AWS CLI found: $(aws --version)"
fi
echo

# Step 0b: Check if Claude Code is installed, install if missing
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
            _unquarantine "/Applications/Claude.app"
            _unquarantine "$(brew --prefix)/bin/claude" 2>/dev/null || true
        elif command -v npm &> /dev/null; then
            echo "Official installer blocked, trying npm..."
            npm install -g @anthropic-ai/claude-code
        else
            echo ""
            echo "⚠️  Could not install Claude Code automatically."
            echo "   Try one of:"
            echo "     brew install --cask claude-code"
            echo "     npm install -g @anthropic-ai/claude-code"
            exit 1
        fi
    fi

    if ! command -v claude &> /dev/null; then
        echo "⚠️  Claude Code installation failed. Please install manually:"
        echo "   brew install --cask claude-code"
        exit 1
    fi
    echo "✓ Claude Code CLI installed: $(claude --version)"
    echo
else
    echo "✓ Claude Code CLI found: $(claude --version)"
fi
echo

START_DIR="$(pwd)"

echo "Downloading package..."
curl -fLk --progress-bar -o "$PACKAGE_FILE" "$PACKAGE_URL"
echo "✓ Downloaded"

echo "Extracting..."
unzip -qo "$PACKAGE_FILE" -d "$PACKAGE_DIR"
echo "✓ Extracted"

echo "Running installer..."
INSTALL_DIR="$PACKAGE_DIR"
if [ ! -f "$PACKAGE_DIR/install.sh" ] && [ -d "$PACKAGE_DIR/$PACKAGE_DIR" ]; then
    INSTALL_DIR="$PACKAGE_DIR/$PACKAGE_DIR"
fi
chmod +x "$INSTALL_DIR/install.sh"
cd "$INSTALL_DIR"
./install.sh

cd "$START_DIR"
rm -rf "$PACKAGE_FILE" "$PACKAGE_DIR"
echo "✓ Cleaned up temporary files"

echo "======================================"
echo "Testing authentication..."
echo "======================================"
export AWS_PROFILE=theiconic-claude-primary

TEST_OUTPUT=$("$HOME/claude-code-with-bedrock/credential-process" --profile theiconic-claude-primary 2>&1)
if echo "$TEST_OUTPUT" | grep -q '"Version"' && echo "$TEST_OUTPUT" | grep -q '"AccessKeyId"'; then
    echo "✓ Authentication working — credentials obtained successfully"
else
    echo "✗ Authentication test failed. Output:"
    echo "$TEST_OUTPUT"
    exit 1
fi
