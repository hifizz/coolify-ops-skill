#!/usr/bin/env bash
# install-cli.sh — install the official Coolify CLI (coollabsio/coolify-cli)
# Supports macOS / Linux with auto-detection; idempotent, skips if already installed.
# Install order: official curl script → Homebrew → `go install` (whichever is available).
set -euo pipefail

if command -v coolify >/dev/null 2>&1; then
  echo "✅ coolify CLI already installed: $(coolify version 2>/dev/null || echo 'version unknown')"
  echo "   To upgrade: coolify update"
  exit 0
fi

echo "📦 coolify CLI not detected, starting installation..."

# Each method returns non-zero (without aborting the script) if its tool is missing or it fails,
# so the `||` chain below can fall through to the next option.
try_official() {
  command -v curl >/dev/null 2>&1 || return 1
  echo "→ Trying official install script (curl)…"
  # pipefail (set above) makes the pipe fail if curl itself fails, so a 4xx/5xx won't be masked.
  curl -fsSL https://raw.githubusercontent.com/coollabsio/coolify-cli/main/scripts/install.sh | bash
}

try_brew() {
  command -v brew >/dev/null 2>&1 || return 1
  echo "→ Trying Homebrew…"
  brew install coollabsio/coolify-cli/coolify-cli
}

try_go() {
  command -v go >/dev/null 2>&1 || return 1
  echo "→ Trying 'go install'…"
  go install github.com/coollabsio/coolify-cli/coolify@latest
}

OS="$(uname -s)"
case "$OS" in
  Darwin|Linux)
    try_official || try_brew || try_go || {
      echo "❌ No install method succeeded (curl / brew / go were unavailable or failed)."
      echo "   Try one of these manually:"
      echo "     • Homebrew: brew install coollabsio/coolify-cli/coolify-cli"
      echo "     • Go:       go install github.com/coollabsio/coolify-cli/coolify@latest"
      echo "     • Releases: https://github.com/coollabsio/coolify-cli/releases"
      exit 1
    }
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
  echo "✅ Installed successfully: $(coolify version 2>/dev/null || echo 'coolify present')"
  echo ""
  echo "Next steps:"
  echo "  1. Generate a token at /security/api-tokens in the Coolify Web UI"
  echo "  2. coolify context add <name> <url> <token> -d"
  echo "  3. coolify context verify"
else
  echo "⚠️  Install finished but coolify is still not on PATH."
  echo "   - If installed via 'go install', add \"$(go env GOPATH 2>/dev/null || echo "\$HOME/go")/bin\" to your PATH."
  echo "   - Otherwise check that /usr/local/bin is in \$PATH, or reopen your terminal."
  exit 1
fi
