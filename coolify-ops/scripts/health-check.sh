#!/usr/bin/env bash
# health-check.sh — Coolify 一键体检
# 检查：CLI 是否在 → context 是否通 → 各资源状态
# 用法：bash health-check.sh [context-name]
#   不传 context-name 则用默认 context
set -uo pipefail

CTX_FLAG=""
if [ "${1:-}" != "" ]; then
  CTX_FLAG="--context=$1"
  echo "🔍 使用 context: $1"
fi

# 1. CLI 在不在
echo "── 1/4 检查 CLI ──"
if ! command -v coolify >/dev/null 2>&1; then
  echo "❌ 找不到 coolify CLI。先运行 install-cli.sh"
  exit 1
fi
echo "✅ $(coolify --version 2>/dev/null || echo coolify present)"

# 2. context 通不通
echo ""
echo "── 2/4 验证连接 ──"
if ! coolify $CTX_FLAG context verify 2>&1; then
  echo "❌ context 验证失败。排查："
  echo "   - URL 是否正确、可达（curl -I <url>）"
  echo "   - token 是否有效（Web UI /security/api-tokens）"
  echo "   - VPS 防火墙是否放行 Coolify 端口"
  exit 1
fi

# 3. 后端版本
echo ""
echo "── 3/4 Coolify 后端版本 ──"
coolify $CTX_FLAG context version 2>/dev/null || echo "(版本查询跳过)"

# 4. 资源状态总览
echo ""
echo "── 4/4 资源状态 ──"
if command -v jq >/dev/null 2>&1; then
  RES="$(coolify $CTX_FLAG resources list --format=json 2>/dev/null)"
  if [ -n "$RES" ] && echo "$RES" | jq empty 2>/dev/null; then
    TOTAL=$(echo "$RES" | jq 'length')
    echo "资源总数：$TOTAL"
    echo ""
    echo "⚠️  非 running 状态的资源："
    UNHEALTHY=$(echo "$RES" | jq -r '.[] | select(.status != null and (.status | test("running") | not)) | "  - \(.name): \(.status)"')
    if [ -z "$UNHEALTHY" ]; then
      echo "  （无，全部正常 ✅）"
    else
      echo "$UNHEALTHY"
    fi
  else
    echo "（拿到的不是合法 JSON，降级为 table 输出）"
    coolify $CTX_FLAG resources list
  fi
else
  echo "（未装 jq，直接表格输出）"
  coolify $CTX_FLAG resources list
fi

echo ""
echo "✅ 体检完成"
