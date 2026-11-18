#!/usr/bin/env bash
#
# verify.sh - check that Playwright MCP is installed and configured correctly.
#
# Every check prints PASS, WARN or FAIL. The script exits with status 1 if any
# check fails, so it can be used in automation.
#
# Usage:
#   ./verify.sh
#   ./verify.sh --config ~/.config/opencode/opencode.json
#
# Environment variables:
#   OPENCODE_CONFIG   configuration file to inspect
#   OPENCODE_AGENTS   instruction file to inspect
#   PLAYWRIGHT_MCP_PROFILE_ROOT   profile directory root

set -uo pipefail

CONFIG_FILE="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"
AGENTS_FILE="${OPENCODE_AGENTS:-$HOME/.config/opencode/AGENTS.md}"
PROFILE_ROOT="${PLAYWRIGHT_MCP_PROFILE_ROOT:-$HOME/.cache/playwright-mcp}"

FAILURES=0

pass() { printf '  \033[1;32mPASS\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33mWARN\033[0m  %s\n' "$*"; }
fail() { printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

section "Runtime"

if command -v node >/dev/null 2>&1; then
  NODE_VERSION="$(node -p 'process.versions.node')"
  NODE_MAJOR="${NODE_VERSION%%.*}"
  if [ "$NODE_MAJOR" -ge 20 ]; then
    pass "Node.js $NODE_VERSION"
  else
    fail "Node.js $NODE_VERSION is older than 20"
  fi
else
  fail "Node.js is not installed"
fi

if command -v npx >/dev/null 2>&1; then
  pass "npx is available"
else
  fail "npx is not available"
fi

if command -v python3 >/dev/null 2>&1; then
  pass "python3 is available"
else
  warn "python3 is missing, setup.sh cannot merge configuration safely"
fi

if command -v opencode >/dev/null 2>&1; then
  pass "opencode $(opencode --version 2>/dev/null | head -n1)"
else
  warn "opencode is not installed, other clients can still use the server"
fi

section "Playwright MCP package"

if MCP_VERSION="$(npx -y @playwright/mcp@latest --version 2>/dev/null | tail -n1)"; then
  pass "package responds: ${MCP_VERSION:-unknown version}"
else
  fail "could not run npx @playwright/mcp@latest --version"
fi

section "Browser engines"

if [ -d "$HOME/.cache/ms-playwright" ]; then
  if compgen -G "$HOME/.cache/ms-playwright/chromium-*" >/dev/null; then
    pass "Chromium engine present"
  else
    fail "Chromium engine missing, run: npx -y playwright@latest install chromium"
  fi

  if compgen -G "$HOME/.cache/ms-playwright/firefox-*" >/dev/null; then
    pass "Firefox engine present"
  else
    warn "Firefox engine missing, optional: npx -y playwright@latest install firefox"
  fi
else
  fail "$HOME/.cache/ms-playwright does not exist, run setup.sh"
fi

section "Profiles"

for name in profile-chrome profile-burp output; do
  if [ -d "$PROFILE_ROOT/$name" ]; then
    pass "$PROFILE_ROOT/$name"
  else
    fail "$PROFILE_ROOT/$name is missing, run setup.sh"
  fi
done

section "Configuration"

if [ ! -f "$CONFIG_FILE" ]; then
  fail "$CONFIG_FILE does not exist, run setup.sh"
else
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$CONFIG_FILE" 2>/dev/null; then
    pass "$CONFIG_FILE is valid JSON"
  else
    fail "$CONFIG_FILE is not valid JSON"
  fi

  RESULT="$(python3 - "$CONFIG_FILE" <<'PYTHON'
import json
import sys

try:
    with open(sys.argv[1]) as handle:
        config = json.load(handle)
except Exception:
    print("unreadable")
    raise SystemExit(0)

servers = config.get("mcp", {}).get("servers", {})
if not servers:
    print("no-servers")
else:
    playwright = servers.get("playwright")
    if not playwright:
        print("no-playwright")
    elif playwright.get("type") != "local":
        print("wrong-type")
    else:
        print("ok:" + ",".join(sorted(servers)))
PYTHON
)"

  case "$RESULT" in
    ok:*)           pass "servers configured: ${RESULT#ok:}" ;;
    no-servers)     fail "no MCP servers found under mcp.servers (version 2 shape required)" ;;
    no-playwright)  fail "the playwright server entry is missing" ;;
    wrong-type)     fail "the playwright entry must have type set to local" ;;
    *)              fail "could not read the server list" ;;
  esac
fi

section "Agent instructions"

if [ -f "$AGENTS_FILE" ] && grep -qF "# Browser (playwright MCP)" "$AGENTS_FILE"; then
  pass "browser rules present in $AGENTS_FILE"
else
  warn "browser rules not found in $AGENTS_FILE, agents may not choose the tools"
fi

section "Display"

if [ -n "${DISPLAY:-}" ]; then
  pass "DISPLAY is set to $DISPLAY, headed browsers will open"
else
  warn "DISPLAY is not set, use --headless entries or a desktop session"
fi

section "Result"

if [ "$FAILURES" -eq 0 ]; then
  printf '  \033[1;32mAll checks passed.\033[0m\n'
  printf '  Run "opencode mcp list" from a project folder to see the connection state.\n\n'
  exit 0
else
  printf '  \033[1;31m%d check(s) failed.\033[0m See PLAYWRIGHT-MCP-SETUP.md section 12.\n\n' "$FAILURES"
  exit 1
fi
