#!/usr/bin/env bash
# deploy-and-watch.sh — trigger a deployment and follow the logs, returning only on success/failed
# Usage:
#   bash deploy-and-watch.sh <app-name>            # deploy by name (recommended)
#   bash deploy-and-watch.sh --uuid <app-uuid>     # deploy by uuid
#   bash deploy-and-watch.sh <app-name> --context staging
set -uo pipefail

CTX_FLAG=""
BY_UUID=0
TARGET=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --uuid) BY_UUID=1; TARGET="$2"; shift 2 ;;
    --context) CTX_FLAG="--context=$2"; shift 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Usage: bash deploy-and-watch.sh <app-name> [--context <name>]"
  echo "  or:  bash deploy-and-watch.sh --uuid <app-uuid>"
  exit 1
fi

command -v coolify >/dev/null 2>&1 || { echo "❌ coolify CLI not found"; exit 1; }

# Resolve the app uuid (following logs requires a uuid)
APP_UUID=""
if [ "$BY_UUID" -eq 1 ]; then
  APP_UUID="$TARGET"
elif command -v jq >/dev/null 2>&1; then
  APP_UUID="$(coolify $CTX_FLAG app list --format=json 2>/dev/null \
    | jq -r --arg n "$TARGET" '.[] | select(.name==$n) | .uuid' | head -n1)"
  if [ -z "$APP_UUID" ] || [ "$APP_UUID" = "null" ]; then
    echo "⚠️  Could not resolve a uuid from name '$TARGET' (the name may not match any app)."
    echo "   Deployment will still be triggered by name, but logs cannot be followed automatically."
    APP_UUID=""
  fi
else
  echo "⚠️  jq not installed — cannot resolve uuid from name '$TARGET'."
  echo "   Deployment will still be triggered by name, but logs cannot be followed automatically."
fi

# Trigger the deployment
echo "🚀 Triggering deployment: $TARGET"
if [ "$BY_UUID" -eq 1 ]; then
  coolify $CTX_FLAG deploy uuid "$TARGET" || { echo "❌ Failed to trigger deployment"; exit 1; }
else
  coolify $CTX_FLAG deploy name "$TARGET" || { echo "❌ Failed to trigger deployment"; exit 1; }
fi

if [ -z "$APP_UUID" ]; then
  echo "ℹ️  No uuid, cannot follow automatically. Check manually:"
  echo "   coolify $CTX_FLAG deploy list"
  exit 0
fi

# Follow the deployment logs (-f keeps streaming until the deployment finishes)
echo ""
echo "📜 Following deployment logs (Ctrl-C stops following; the deployment keeps running in the background)..."
echo "────────────────────────────────────────"
coolify $CTX_FLAG app deployments logs "$APP_UUID" -f

# After following ends, report the final status.
# Use `app deployments list <app-uuid>` — it is already scoped to this app, so we
# don't have to filter the global `deploy list` by uuid. (The global list has no
# reliable app-UUID column: `application_id` is an internal numeric id, not the
# app uuid, so matching it against $APP_UUID never works for by-uuid deploys.)
echo "────────────────────────────────────────"
echo "🔎 Latest deployment status:"
if command -v jq >/dev/null 2>&1; then
  coolify $CTX_FLAG app deployments list "$APP_UUID" --format=json 2>/dev/null \
    | jq -r 'sort_by(.created_at) | last
             | "  Status: \(.status // "unknown")  Deployment ID: \(.deployment_uuid // .uuid // "?")"' \
    2>/dev/null || coolify $CTX_FLAG app deployments list "$APP_UUID"
else
  coolify $CTX_FLAG app deployments list "$APP_UUID"
fi
