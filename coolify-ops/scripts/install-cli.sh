#!/usr/bin/env bash
# install-cli.sh — 安装官方 Coolify CLI（coollabsio/coolify-cli）
# 支持 macOS / Linux，自动检测；幂等，已装则跳过。
set -euo pipefail

if command -v coolify >/dev/null 2>&1; then
  echo "✅ coolify CLI 已安装：$(coolify --version 2>/dev/null || echo '版本未知')"
  echo "   如需升级：coolify update"
  exit 0
fi

echo "📦 未检测到 coolify CLI，开始安装..."

OS="$(uname -s)"
case "$OS" in
  Darwin|Linux)
    # 官方安装脚本（装到 /usr/local/bin/coolify）
    curl -fsSL https://raw.githubusercontent.com/coollabsio/coolify-cli/main/scripts/install.sh | bash
    ;;
  *)
    echo "❌ 不支持的系统：$OS"
    echo "   Windows 请用 PowerShell 运行："
    echo "   irm https://raw.githubusercontent.com/coollabsio/coolify-cli/main/scripts/install.ps1 | iex"
    exit 1
    ;;
esac

# 验证
if command -v coolify >/dev/null 2>&1; then
  echo "✅ 安装成功：$(coolify --version)"
  echo ""
  echo "下一步："
  echo "  1. 去 Coolify Web UI 的 /security/api-tokens 生成 token"
  echo "  2. coolify context add <name> <url> <token> -d"
  echo "  3. coolify context verify"
else
  echo "⚠️  安装脚本跑完了但 PATH 里还找不到 coolify。"
  echo "   检查 /usr/local/bin 是否在 \$PATH 中，或重开终端。"
  exit 1
fi
