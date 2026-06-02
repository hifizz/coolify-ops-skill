#!/usr/bin/env bash
# deploy-and-watch.sh — 触发部署并跟随日志，直到 success/failed 才返回
# 用法：
#   bash deploy-and-watch.sh <app-name>            # 按名字部署（推荐）
#   bash deploy-and-watch.sh --uuid <app-uuid>     # 按 uuid 部署
#   bash deploy-and-watch.sh <app-name> --context staging
set -uo pipefail

CTX_FLAG=""
BY_UUID=0
TARGET=""

# 解析参数
while [ $# -gt 0 ]; do
  case "$1" in
    --uuid) BY_UUID=1; TARGET="$2"; shift 2 ;;
    --context) CTX_FLAG="--context=$2"; shift 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "用法：bash deploy-and-watch.sh <app-name> [--context <name>]"
  echo "  或：bash deploy-and-watch.sh --uuid <app-uuid>"
  exit 1
fi

command -v coolify >/dev/null 2>&1 || { echo "❌ 找不到 coolify CLI"; exit 1; }

# 解析出 app uuid（跟日志需要 uuid）
APP_UUID="$TARGET"
if [ "$BY_UUID" -eq 0 ]; then
  if command -v jq >/dev/null 2>&1; then
    APP_UUID="$(coolify $CTX_FLAG app list --format=json 2>/dev/null \
      | jq -r --arg n "$TARGET" '.[] | select(.name==$n) | .uuid' | head -n1)"
  fi
  if [ -z "$APP_UUID" ] || [ "$APP_UUID" = "null" ]; then
    echo "⚠️  没能从名字 '$TARGET' 解析出 uuid（可能没装 jq 或名字不匹配）。"
    echo "   仍会按名字触发部署，但无法自动跟日志。"
    APP_UUID=""
  fi
fi

# 触发部署
echo "🚀 触发部署：$TARGET"
if [ "$BY_UUID" -eq 1 ]; then
  coolify $CTX_FLAG deploy uuid "$TARGET" || { echo "❌ 部署触发失败"; exit 1; }
else
  coolify $CTX_FLAG deploy name "$TARGET" || { echo "❌ 部署触发失败"; exit 1; }
fi

if [ -z "$APP_UUID" ]; then
  echo "ℹ️  无 uuid，无法自动跟随。手动查看："
  echo "   coolify $CTX_FLAG deploy list"
  exit 0
fi

# 跟随部署日志（-f 会持续输出到部署结束）
echo ""
echo "📜 跟随部署日志（Ctrl-C 可中断跟随，部署仍在后台继续）..."
echo "────────────────────────────────────────"
coolify $CTX_FLAG app deployments logs "$APP_UUID" -f

# 跟随结束后给出最终状态
echo "────────────────────────────────────────"
echo "🔎 最近部署状态："
if command -v jq >/dev/null 2>&1; then
  # ⚠️ 字段名（application_uuid / resource_uuid / deployment_uuid / status）是基于通用约定推断的，未在真实 CLI 上验证。
  #    首次使用请先跑 `coolify deploy list --format=json` 核对真实字段名，再依赖下面的过滤；
  #    若字段名不符，jq 会过滤不到结果而自动降级为 `coolify deploy list`（表格）输出。
  coolify $CTX_FLAG deploy list --format=json 2>/dev/null \
    | jq -r --arg u "$APP_UUID" '[.[] | select(.application_uuid==$u or .resource_uuid==$u)] | sort_by(.created_at) | last | "  状态: \(.status // "unknown")  部署ID: \(.deployment_uuid // .uuid // "?")"' \
    2>/dev/null || coolify $CTX_FLAG deploy list
else
  coolify $CTX_FLAG deploy list
fi
