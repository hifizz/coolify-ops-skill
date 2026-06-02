#!/usr/bin/env bash
# install-cli.sh — install the official Coolify CLI (coollabsio/coolify-cli)
# Supports macOS / Linux with auto-detection; idempotent, skips if already installed.
set -euo pipefail

if command -v coolify >/dev/null 2>&1; then
  echo "✅ coolify CLI already installed: $(coolify --version 2>/dev/null || echo 'version unknown')"
  echo "   To upgrade: coolify update"
  exit 0
fi

echo "📦 coolify CLI not detected, starting installation..."

OS="$(uname -s)"
case "$OS" in
  Darwin|Linux)
    # Official install script (installs to /usr/local/bin/coolify)
    curl -fsSL https://raw.githubusercontent.com/coollabsio/coolify-cli/main/scripts/install.sh | bash
    ;;
  *)
    echo "❌ Unsupported system: $OS"
    echo "   On Windows, run in PowerShell:"
    echo "   irm https://raw.githubusercontent.com/coollabsio/coolify-cli/main/scripts/install.ps1 | iex"
    exit 1
    ;;
esac

# Verify
if command -v coolify >/dev/null 2>&1; then
  echo "✅ Installed successfully: $(coolify --version)"
  echo ""
  echo "Next steps:"
  echo "  1. Generate a token at /security/api-tokens in the Coolify Web UI"
  echo "  2. coolify context add <name> <url> <token> -d"
  echo "  3. coolify context verify"
else
  echo "⚠️  Install script finished but coolify is still not on PATH."
  echo "   Check that /usr/local/bin is in \$PATH, or reopen your terminal."
  exit 1
fi
