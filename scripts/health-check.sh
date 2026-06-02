#!/usr/bin/env bash
# health-check.sh — one-shot Coolify health check
# Checks: is the CLI present -> is the context reachable -> status of each resource
# Usage: bash health-check.sh [context-name]
#   Omit context-name to use the default context
set -uo pipefail

CTX_FLAG=""
if [ "${1:-}" != "" ]; then
  CTX_FLAG="--context=$1"
  echo "🔍 Using context: $1"
fi

# 1. Is the CLI present
echo "── 1/4 Checking CLI ──"
if ! command -v coolify >/dev/null 2>&1; then
  echo "❌ coolify CLI not found. Run install-cli.sh first"
  exit 1
fi
echo "✅ $(coolify version 2>/dev/null || echo coolify present)"

# 2. Is the context reachable
echo ""
echo "── 2/4 Verifying connection ──"
if ! coolify $CTX_FLAG context verify 2>&1; then
  echo "❌ Context verification failed. Troubleshooting:"
  echo "   - Is the URL correct and reachable (curl -I <url>)"
  echo "   - Is the token valid (Web UI /security/api-tokens)"
  echo "   - Does the VPS firewall allow the Coolify port"
  exit 1
fi

# 3. Backend version
echo ""
echo "── 3/4 Coolify backend version ──"
coolify $CTX_FLAG context version 2>/dev/null || echo "(version query skipped)"

# 4. Resource status overview
echo ""
echo "── 4/4 Resource status ──"
if command -v jq >/dev/null 2>&1; then
  RES="$(coolify $CTX_FLAG resources list --format=json 2>/dev/null)"
  if [ -n "$RES" ] && echo "$RES" | jq empty 2>/dev/null; then
    TOTAL=$(echo "$RES" | jq 'length')
    echo "Total resources: $TOTAL"
    echo ""
    echo "⚠️  Resources not in running state:"
    UNHEALTHY=$(echo "$RES" | jq -r '.[] | select(.status != null and (.status | startswith("running") | not)) | "  - \(.name): \(.status)"')
    if [ -z "$UNHEALTHY" ]; then
      echo "  (none, all healthy ✅)"
    else
      echo "$UNHEALTHY"
    fi
  else
    echo "(response is not valid JSON, falling back to table output)"
    coolify $CTX_FLAG resources list
  fi
else
  echo "(jq not installed, printing table output directly)"
  coolify $CTX_FLAG resources list
fi

echo ""
echo "✅ Health check complete"
