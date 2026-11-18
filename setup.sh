#!/usr/bin/env bash
#
# setup.sh - install and configure Playwright MCP for AI agents.
#
# What it does:
#   1. Checks that Node.js and npx are available and new enough.
#   2. Installs the Playwright browser engines (Chromium and Firefox).
#   3. Creates the browser profile directories that keep logins persistent.
#   4. Merges the Playwright MCP server entries into your OpenCode configuration.
#   5. Adds the browser usage rules to your global agent instructions.
#
# Design rules:
#   - Safe to run again at any time. Existing entries are left untouched unless
#     you pass --force.
#   - Never calls sudo and never touches system packages.
#   - Never deletes or overwrites unrelated configuration.
#   - Always writes a timestamped backup before editing a file.
#
# Usage:
#   ./setup.sh                     install everything with default settings
#   ./setup.sh --dry-run           show what would happen, change nothing
#   ./setup.sh --burp-port 8081    use a different Burp or ZAP proxy port
#   ./setup.sh --no-browsers       skip the browser download step
#   ./setup.sh --force             rewrite the server entries even if present
#
# Exit codes:
#   0 success, 1 environment problem, 2 invalid argument.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

BURP_PORT="${BURP_PORT:-8080}"
PROFILE_ROOT="${PLAYWRIGHT_MCP_PROFILE_ROOT:-$HOME/.cache/playwright-mcp}"
CONFIG_FILE="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"
AGENTS_FILE="${OPENCODE_AGENTS:-$HOME/.config/opencode/AGENTS.md}"

DRY_RUN=0
FORCE=0
INSTALL_BROWSERS=1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ ok ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
die()   { printf '\033[1;31m[fail]\033[0m  %s\n' "$*" >&2; exit 1; }

# Run a command, or only print it when --dry-run is active.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '       would run: %s\n' "$*"
  else
    "$@"
  fi
}

usage() {
  cat <<'EOF'
Playwright MCP setup for AI agents

Options:
  --burp-port <port>     Port of your Burp Suite or ZAP proxy (default: 8080)
  --profile-root <dir>   Where browser profiles are stored
                         (default: ~/.cache/playwright-mcp)
  --config <file>        OpenCode configuration file to edit
                         (default: ~/.config/opencode/opencode.json)
  --no-browsers          Do not download the Playwright browser engines
  --force                Overwrite existing Playwright server entries
  --dry-run              Print every action without changing anything
  -h, --help             Show this help

Environment variables with the same effect:
  BURP_PORT, PLAYWRIGHT_MCP_PROFILE_ROOT, OPENCODE_CONFIG, OPENCODE_AGENTS
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --burp-port)     BURP_PORT="${2:-}"; shift 2 ;;
    --profile-root)  PROFILE_ROOT="${2:-}"; shift 2 ;;
    --config)        CONFIG_FILE="${2:-}"; shift 2 ;;
    --no-browsers)   INSTALL_BROWSERS=0; shift ;;
    --force)         FORCE=1; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               printf 'Unknown option: %s\n\n' "$1" >&2; usage; exit 2 ;;
  esac
done

[ -n "$BURP_PORT" ]     || die "--burp-port needs a value"
[ -n "$PROFILE_ROOT" ]  || die "--profile-root needs a value"
[ -n "$CONFIG_FILE" ]   || die "--config needs a value"

# ---------------------------------------------------------------------------
# Step 1: environment checks
# ---------------------------------------------------------------------------

info "Checking the environment"

command -v node >/dev/null 2>&1 || die "Node.js is not installed. Install Node.js 20 or newer first."
command -v npx  >/dev/null 2>&1 || die "npx is not available. It ships with npm, which ships with Node.js."
command -v python3 >/dev/null 2>&1 || die "python3 is required to edit the configuration file safely."

NODE_VERSION="$(node -p 'process.versions.node')"
NODE_MAJOR="${NODE_VERSION%%.*}"
if [ "$NODE_MAJOR" -lt 20 ]; then
  die "Node.js $NODE_VERSION is too old. Version 20 or newer is required."
fi
ok "Node.js $NODE_VERSION"

if [ "$INSTALL_BROWSERS" -eq 1 ]; then
  info "Installing Playwright browser engines (Chromium and Firefox)"
  info "This is a one-time download of roughly one gigabyte."
  run npx -y playwright@latest install chromium firefox
  ok "Browser engines installed"
else
  warn "Skipping the browser download because --no-browsers was given"
fi

# ---------------------------------------------------------------------------
# Step 2: profile directories
# ---------------------------------------------------------------------------

info "Creating profile directories under $PROFILE_ROOT"

for name in profile-chrome profile-burp profile-scratch profile-chromium profile-firefox output output-scratch; do
  run mkdir -p "$PROFILE_ROOT/$name"
done
ok "Profile directories ready"

# ---------------------------------------------------------------------------
# Step 3: OpenCode configuration
# ---------------------------------------------------------------------------

info "Updating $CONFIG_FILE"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$(dirname "$CONFIG_FILE")"
  if [ -f "$CONFIG_FILE" ]; then
    BACKUP="$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$CONFIG_FILE" "$BACKUP"
    ok "Backup written to $BACKUP"
  else
    printf '{}\n' > "$CONFIG_FILE"
    ok "Created a new configuration file"
  fi

  CONFIG_FILE="$CONFIG_FILE" \
  PROFILE_ROOT="$PROFILE_ROOT" \
  BURP_PORT="$BURP_PORT" \
  FORCE="$FORCE" \
  python3 - <<'PYTHON'
import json
import os
import sys

config_path  = os.environ["CONFIG_FILE"]
profile_root = os.environ["PROFILE_ROOT"]
burp_port    = os.environ["BURP_PORT"]
force        = os.environ["FORCE"] == "1"

with open(config_path) as handle:
    try:
        config = json.load(handle)
    except json.JSONDecodeError as error:
        sys.exit(f"The configuration file is not valid JSON: {error}")

config.setdefault("$schema", "https://opencode.ai/config.json")
servers = config.setdefault("mcp", {}).setdefault("servers", {})

base = ["npx", "-y", "@playwright/mcp@latest"]

shared = [
    "--output-dir", f"{profile_root}/output",
    "--timeout-action", "15000",
    "--console-level", "warning",
    "--idle-timeout", "1800000",
    "--caps", "network,storage",
]

entries = {
    "playwright": {
        "type": "local",
        "command": base + [
            "--browser", "chrome",
            "--user-data-dir", f"{profile_root}/profile-chrome",
            "--timeout-navigation", "90000",
        ] + shared,
        "timeout": {"startup": 120000, "execution": 1800000},
    },
    "playwright-burp": {
        "type": "local",
        "command": base + [
            "--browser", "chrome",
            "--user-data-dir", f"{profile_root}/profile-burp",
            "--proxy-server", f"http://127.0.0.1:{burp_port}",
            "--proxy-bypass", "localhost,127.0.0.1,::1",
            "--ignore-https-errors",
            "--timeout-navigation", "120000",
        ] + shared,
        "timeout": {"startup": 120000, "execution": 1800000},
    },
    "playwright-scratch": {
        "type": "local",
        "disabled": True,
        "command": base + [
            "--browser", "chrome",
            "--isolated",
            "--headless",
            "--output-dir", f"{profile_root}/output-scratch",
            "--timeout-action", "15000",
            "--timeout-navigation", "90000",
            "--console-level", "warning",
            "--idle-timeout", "900000",
            "--caps", "network,storage",
        ],
        "timeout": {"startup": 120000, "execution": 1800000},
    },
    "playwright-chromium": {
        "type": "local",
        "disabled": True,
        "command": base + [
            "--user-data-dir", f"{profile_root}/profile-chromium",
        ] + shared,
    },
    "playwright-firefox": {
        "type": "local",
        "disabled": True,
        "command": base + [
            "--browser", "firefox",
            "--user-data-dir", f"{profile_root}/profile-firefox",
        ] + shared,
    },
}

added, skipped = [], []
for name, entry in entries.items():
    if name in servers and not force:
        skipped.append(name)
        continue
    servers[name] = entry
    added.append(name)

with open(config_path, "w") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")

print(f"       added or updated: {', '.join(added) if added else 'none'}")
print(f"       left untouched:   {', '.join(skipped) if skipped else 'none'}")
PYTHON
  ok "Configuration updated"
else
  printf '       would merge 5 server entries into %s\n' "$CONFIG_FILE"
fi

# ---------------------------------------------------------------------------
# Step 4: global agent instructions
# ---------------------------------------------------------------------------

info "Updating $AGENTS_FILE"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$(dirname "$AGENTS_FILE")"
  touch "$AGENTS_FILE"

  if grep -qF "# Browser (playwright MCP)" "$AGENTS_FILE"; then
    ok "Browser rules already present, nothing to add"
  else
    BACKUP="$AGENTS_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$AGENTS_FILE" "$BACKUP"

    if [ -s "$AGENTS_FILE" ]; then
      printf '\n' >> "$AGENTS_FILE"
    fi

    cat >> "$AGENTS_FILE" <<'MARKDOWN'
# Browser (playwright MCP)

When a task needs a real browser - a login, a JavaScript-heavy page, a form, a
screenshot, an authenticated session, or pentest and bug bounty reconnaissance -
use the playwright MCP tools directly. Do not install a browser, do not launch one
from the shell, and do not fall back to curl or requests for JavaScript-rendered
pages.

- Work in a loop: navigate, take a snapshot, act on an element reference, then take
  another snapshot.
- Never assume that a click worked. Take a new snapshot after any action that
  changes the page.
- Use the `playwright` server for direct traffic. Use `playwright-burp` only when
  traffic must go through Burp Suite or ZAP, which must be listening on port 8080,
  otherwise every request fails with ERR_PROXY_CONNECTION_FAILED.
- A browser profile can only be used by one browser process at a time. If a launch
  fails with a lock error, another session is using the same profile. Report it
  instead of retrying in a loop.
- The full setup and usage guide is in PLAYWRIGHT-MCP-SETUP.md.
MARKDOWN
    ok "Browser rules appended (backup written)"
  fi
else
  printf '       would append the browser rules to %s if absent\n' "$AGENTS_FILE"
fi

# ---------------------------------------------------------------------------
# Step 5: summary
# ---------------------------------------------------------------------------

cat <<EOF

Setup finished.

  Configuration : $CONFIG_FILE
  Instructions  : $AGENTS_FILE
  Profiles      : $PROFILE_ROOT
  Burp port     : $BURP_PORT

Next steps:

  1. Verify the installation:
       ./verify.sh

  2. Confirm that OpenCode sees the servers, run from a project folder:
       opencode mcp list

  3. Ask your agent to test the browser:
       Use playwright to open https://demo.playwright.dev/todomvc, add two tasks,
       and confirm that both appear.

  4. To send traffic through Burp Suite, start Burp first and then enable the
     playwright-burp server by setting "disabled" to false in the configuration.

EOF
