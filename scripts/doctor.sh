#!/usr/bin/env bash
# doctor.sh — preflight self-check for coolify-ops. Run this first after install, or
# whenever something is off. Checks four things and prints a one-screen verdict:
#   1) coolify CLI present & version ≥ the verified baseline
#   2) jq present (needed to extract UUIDs / parse JSON)
#   3) context connectivity + auth (coolify context verify)
#   4) token abilities — a read probe + a non-destructive deploy probe
# Usage: bash doctor.sh [context-name]   (omit the name to use the default context)
set -uo pipefail

MIN_VER="1.6.2"
CTX_FLAG=""
if [ "${1:-}" != "" ]; then
  CTX_FLAG="--context=$1"
  echo "🔍 Using context: $1"
fi

WARN=0; FAIL=0
ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; WARN=$((WARN+1)); }
bad()  { echo "  ❌ $*"; FAIL=$((FAIL+1)); }

# ── 1/4 CLI + version ──
echo "── 1/4 coolify CLI ──"
if ! command -v coolify >/dev/null 2>&1; then
  bad "coolify CLI not found. Run scripts/install-cli.sh first."
  echo ""
  echo "Cannot continue without the CLI."
  exit 1
fi
VER="$(coolify version 2>/dev/null | head -n1 | tr -d '[:space:]')"
VER_NUM="${VER#v}"   # strip an optional leading 'v' — some builds report 'v1.6.2'
if [ -z "$VER" ]; then
  warn "installed, but couldn't read the version."
elif printf '' | sort -V >/dev/null 2>&1; then
  LOWEST="$(printf '%s\n%s\n' "$VER_NUM" "$MIN_VER" | sort -V | head -n1)"
  if [ "$LOWEST" = "$MIN_VER" ]; then
    ok "version $VER (≥ verified baseline $MIN_VER)"
  else
    warn "version $VER is older than the verified baseline $MIN_VER — flags/fields may differ; consider 'coolify update'."
  fi
elif [ "$VER_NUM" = "$MIN_VER" ]; then
  ok "version $VER (matches verified baseline $MIN_VER)"
else
  warn "version $VER (verified baseline is $MIN_VER; this 'sort' can't compare ordering)."
fi

# ── 2/4 jq ──
echo "── 2/4 jq (JSON parsing) ──"
if command -v jq >/dev/null 2>&1; then
  ok "jq present: $(jq --version 2>/dev/null)"
else
  warn "jq not installed — scripts fall back to table output and can't extract UUIDs. Install: 'brew install jq' or 'apt-get install jq'."
fi

# ── 3/4 connectivity + auth ──
echo "── 3/4 context connectivity + auth ──"
if coolify $CTX_FLAG context verify >/dev/null 2>&1; then
  ok "context verified (URL reachable + token valid)"
else
  bad "context verify failed. Check: URL reachable ('curl -I <url>'), token valid (Web UI /security/api-tokens), VPS firewall."
fi

# ── 4/4 token abilities ──
echo "── 4/4 token abilities ──"
# read probe: 'resource list' needs the 'read' ability.
if coolify $CTX_FLAG resource list --format=json >/dev/null 2>&1 </dev/null; then
  ok "read: 'resource list' works → token has 'read'."
else
  ROUT="$(coolify $CTX_FLAG resource list --debug 2>&1 </dev/null || true)"
  if echo "$ROUT" | grep -qiE "403|forbidden|permission"; then
    bad "read: 403 / permission error → token is missing the 'read' ability."
  else
    warn "read: 'resource list' failed but not clearly a 403. Re-run with --debug to inspect."
  fi
fi
# deploy probe: uses a deliberately non-existent target, so NOTHING is ever deployed.
# A token without 'deploy' is rejected with 403 before the target is even checked;
# a token with 'deploy' gets a 404/not-found for the bogus uuid.
DOUT="$(coolify $CTX_FLAG deploy uuid "doctor-probe-nonexistent-uuid" --debug 2>&1 </dev/null || true)"
if echo "$DOUT" | grep -qiE "403|forbidden"; then
  warn "deploy: probe got 403 → token likely lacks the 'deploy' ability (add it in the Web UI if you need to deploy)."
else
  ok "deploy: probe was not rejected with 403 → 'deploy' looks present (the bogus target just 404s; nothing was deployed)."
fi
echo "     ('write' / 'read:sensitive' can't be probed without side effects — grant them per references/safety-rules.md.)"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "Summary: 0 failed, $WARN warning(s). Ready to operate."
else
  echo "Summary: $FAIL failed, $WARN warning(s). Resolve the ❌ items first."
fi
[ "$FAIL" -eq 0 ]
