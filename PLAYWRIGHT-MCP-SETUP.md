---
name: playwright-mcp-setup
description: Install, configure and operate Playwright MCP so that any AI agent can drive a real browser reliably. Use this when a task needs a browser, or when setting up a new machine.
---

# Playwright MCP — Setup and Operating Guide

This document is a complete, tested procedure. It is written so that an AI agent can
perform the entire setup without asking questions, and so that a person can rebuild the
whole environment after reinstalling the operating system.

Everything in the table below was measured on a real machine rather than copied from a
blog post. Where guides that circulate online are wrong, section 13 explains what is
wrong and why.

## How to use this document

| If you are | Do this |
|---|---|
| A person setting up a new machine | Run `./setup.sh` in this repository, then run `./verify.sh`. Consult this document when something needs explaining. |
| An AI agent asked to install this | Read section 0, then run `./setup.sh` and `./verify.sh`, and report the result of `opencode mcp list`. |
| An AI agent asked to use the browser | Read section 0, then follow the loop described in section 5. |
| Someone debugging a failure | Run `./verify.sh`, then look up the exact error message in section 12. |

Prompts that can be pasted directly into an agent:

Install and verify:

```text
Read PLAYWRIGHT-MCP-SETUP.md, run ./setup.sh, then run ./verify.sh. Fix anything that
verify.sh reports as FAIL without using sudo, and show me the output of
opencode mcp list at the end. Do not install the Python Playwright package.
```

Diagnose a problem:

```text
Run ./verify.sh, explain each FAIL and WARN in plain language, and fix what you can
without using sudo.
```

Prove that the browser works:

```text
Use the playwright tools to open https://demo.playwright.dev/todomvc, add two tasks,
and confirm that both are present. Report the page title and the snapshot result.
```

**Verified on**

| Item | Value |
|---|---|
| Operating system | Kali Linux rolling (`7.1.5+kali-amd64`) |
| Node / npx | v24.21.0 / 12.0.2 |
| `@playwright/mcp` | 0.0.83 |
| Playwright engine | 1.64.0-alpha-1790635538000 |
| Bundled Chromium | `chromium-1248`, Chrome for Testing 156.0.8078.4 |
| Bundled Firefox | `firefox-1555`, Firefox 157.0 |
| System Chrome (channel) | Google Chrome 155.0.8059.39 |
| opencode | v2.2.0 (configuration schema: `mcp.servers`) |
| Burp Suite Pro browser | "Burp Browser 151.0.7922.137" |

> Kali is not an officially supported Playwright operating system. The installer prints
> `BEWARE: your OS is not officially supported by Playwright` and downloads the
> `ubuntu24.04-x64` fallback build. This is expected and works correctly.

> The versions above were current when this guide was written. Because the commands use
> `@playwright/mcp@latest`, a newer release may be resolved on your machine; the
> configuration in this document is not tied to a specific version.

---

## 0. Instructions for AI agents

You have browser tools available. Use them. Do not spend turns on any of the following:

| Do not | Do this instead |
|---|---|
| Run `pip install playwright` or `npm install playwright` | The server is already installed. Call its tools. |
| Launch `chrome` or `chromium` from a shell | Call `browser_navigate` |
| Use `curl` or `requests` on a page that needs JavaScript | Call `browser_navigate`, then `browser_snapshot` |
| Take a screenshot in order to understand the page | Call `browser_snapshot`. It is cheaper and more precise. |
| Click by guessing coordinates | Take a snapshot first, then click the element reference |
| Assume that a click succeeded | Take another snapshot after any action that changes the page |
| Try to control Burp Suite's embedded browser | Send Playwright's browser through the Burp proxy (section 8) |

The loop is always the same:

```text
browser_navigate(url) -> browser_snapshot() -> act on a reference -> browser_snapshot()
```

If the tools are missing entirely, run section 11 before doing anything else. If the
server is configured but a call fails, section 12 lists the cause of each error message.

Never point `--user-data-dir` at a person's real browser profile. That profile contains
their email, their bank, and everything else, and it is locked while their browser is
open.

---

## 1. What this is

Playwright automates browsers. Playwright MCP is Microsoft's ready-made MCP server that
exposes browser control to any MCP-capable agent as a set of tools.

```text
AI agent  ->  MCP client  ->  Playwright MCP server  ->  Playwright  ->  Browser
```

| Component | Responsibility |
|---|---|
| Agent | Decides what to do next. |
| MCP client | Starts the server and exposes its tools to the agent. |
| Playwright MCP server | Provides browser tools and returns structured page snapshots. |
| Playwright | Performs the automation and handles waiting. |
| Browser | Renders the page and carries out the interaction. |

**What you get:** navigation, clicking, typing, forms, tabs, file uploads, dialogs,
screenshots, PDF generation, console and network inspection, cookies and storage,
request interception, tracing and video.

**What you do not get:** every method of the full Playwright API. The server exposes a
curated, agent-friendly subset: 25 tools in the core set, 59 with every optional
capability enabled (section 7).

**What you do not need:** a Python installation, a custom MCP server, or a cloned
repository. The published npm package is the entire installation; there is nothing to
build or compile.

---

## 2. Requirements

| Requirement | How to check | Notes |
|---|---|---|
| Node.js 20 or newer, with npx | `node -v && npx -v` | Both ship together |
| An MCP-capable client | - | opencode, Claude Code, Codex, Cursor, VS Code, Claude Desktop |
| A graphical session for visible browsers | `echo $DISPLAY` | For example `:0`. Not required for headless entries |
| Network access, once | - | Roughly one gigabyte of browser engines on the first run |

If Node.js is missing on Debian or Kali:

```bash
sudo apt install -y nodejs npm
```

For a newer version than the distribution provides, use a Node version manager.

Optional, for security work:

| Requirement | Notes |
|---|---|
| Burp Suite or ZAP | Only needed for the proxied server entry |
| Google Chrome | Used by default because its fingerprint resembles a normal browser |

---

## 3. Install (one time)

The repository ships an installer that performs every step in this section:

```bash
./setup.sh
```

The manual equivalent is:

```bash
# 1. Browser engines. Chromium is the fallback, Firefox is the second engine.
npx -y playwright@latest install chromium firefox

# 2. One profile directory per browser entry. Section 6 explains why they must not be shared.
mkdir -p ~/.cache/playwright-mcp/{profile-chrome,profile-burp,profile-scratch,profile-chromium,profile-firefox,output,output-scratch}

# 3. Confirm that the binaries exist and run.
ls ~/.cache/ms-playwright/
~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome --version
```

Details that save time:

- The directory is named **`chrome-linux64`**, not `chrome-linux`. Older guides use the
  wrong name and the path fails.
- Do **not** run `playwright install-deps` on Kali. It resolves Ubuntu package names and
  fails. Install the specific libraries instead (section 12).
- `--browser chrome` uses the system Chrome and needs no download. The bundled Chromium
  exists only as a reproducible fallback.
- WebKit is optional. It requires about 500 MB plus additional system dependencies and is
  rarely needed for security work.

---

## 4. Configure your client

Choose the section for your client. The server command is identical everywhere; only the
surrounding JSON differs.

### 4.1 OpenCode version 2 (current)

File: `~/.config/opencode/opencode.json` for a global configuration, or `./opencode.json`
inside a project. Servers live under **`mcp.servers`**, and a local server requires
**`type: "local"`** with `command` written as an **array**.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "playwright": {
        "type": "local",
        "command": [
          "npx", "-y", "@playwright/mcp@latest",
          "--browser", "chrome",
          "--user-data-dir", "/home/USER/.cache/playwright-mcp/profile-chrome",
          "--output-dir", "/home/USER/.cache/playwright-mcp/output",
          "--timeout-action", "15000",
          "--timeout-navigation", "90000",
          "--console-level", "warning",
          "--idle-timeout", "1800000",
          "--caps", "network,storage"
        ],
        "timeout": { "startup": 120000, "execution": 1800000 }
      }
    }
  }
}
```

Command line alternative that merges instead of overwriting:

```bash
opencode mcp add playwright --global -- npx -y @playwright/mcp@latest --browser chrome
opencode mcp list
```

OpenCode reloads configuration automatically, so no restart is required. Use `/reload` if
the change does not appear. Under the default Code Mode the tools are called as
`tools.playwright.browser_navigate(...)` inside the `execute` tool. Add
`"codemode": false` to the server object if you want them as native tools instead.

> **Version 1 syntax does not work here.** A configuration written as
> `"mcp": { "playwright": { ... "enabled": true } }` belongs to version 1 and is silently
> ignored by version 2. Use `mcp.servers` with `type: "local"`, and use `disabled` rather
> than `enabled` to park a server.

### 4.2 Claude Code

```bash
claude mcp add playwright -- npx -y @playwright/mcp@latest --browser chrome
claude mcp list
```

### 4.3 Codex CLI

```bash
codex mcp add playwright -- npx -y "@playwright/mcp@latest" --browser chrome
codex mcp list
```

### 4.4 Cursor, VS Code, Claude Desktop and other clients

Most of these use a `mcpServers` map with `command` and `args`:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": [
        "-y", "@playwright/mcp@latest",
        "--browser", "chrome",
        "--user-data-dir", "/home/USER/.cache/playwright-mcp/profile-chrome",
        "--output-dir", "/home/USER/.cache/playwright-mcp/output",
        "--idle-timeout", "1800000",
        "--caps", "network,storage"
      ]
    }
  }
}
```

| Client | Configuration file |
|---|---|
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` on macOS, `%APPDATA%\Claude\claude_desktop_config.json` on Windows |
| Cursor | `~/.cursor/mcp.json`, or `.cursor/mcp.json` inside the project |
| VS Code with Copilot | `.vscode/mcp.json` |
| Windsurf, Cline, Kiro, LM Studio | The client's own MCP settings file, same shape |

### 4.5 Tell the agent to use the tools

A server that is configured but never selected is useless. Add the rules below to the
file your client loads as global instructions:

| Client | File |
|---|---|
| OpenCode | `~/.config/opencode/AGENTS.md` |
| Claude Code | `~/.claude/CLAUDE.md` |
| Codex | `~/.codex/AGENTS.md` |
| Cursor | A rule in `.cursor/rules` |

```markdown
# Browser

When a task needs a real browser, use the playwright MCP tools directly. Never install a
browser, never launch one by hand, and never fall back to curl or requests for pages that
need JavaScript.

Work in a loop: browser_navigate, browser_snapshot, act on an element reference, then
snapshot again. Never assume that a click worked.

Use the `playwright` server for direct traffic. Use `playwright-burp` only when traffic
must go through Burp Suite.
```

The repository provides the same text in `config/AGENTS.snippet.md`, and `setup.sh` adds it
automatically.

---

## 5. Using the browser

Ask in natural language and the agent performs the tool loop itself:

> Open https://demo.playwright.dev/todomvc, add two tasks, and verify that both appear.

> Log into this staging application using the credentials in `.env`, then list every form
> field and its validation message.

> Visit `/api/users` as an administrator and then as a normal user, and tell me whether the
> normal user can read the administrator response.

Core tools that are always available:

| Tool | Purpose |
|---|---|
| `browser_navigate` | Open a URL and return a snapshot |
| `browser_snapshot` | The primary observation tool: accessibility tree with element references |
| `browser_click`, `browser_type`, `browser_hover`, `browser_press_key` | Act on an element reference |
| `browser_fill_form` | Fill several fields at once |
| `browser_select_option`, `browser_file_upload`, `browser_drop` | Input handling |
| `browser_wait_for` | Wait for text, an element, or a fixed time |
| `browser_find` | Search the page without taking a full snapshot |
| `browser_evaluate` | Run JavaScript inside the page |
| `browser_take_screenshot` | Capture evidence, or inspect layout |
| `browser_console_messages` | JavaScript errors and application logs |
| `browser_network_requests`, `browser_network_request` | The requests the page actually made |
| `browser_handle_dialog`, `browser_navigate_back`, `browser_tabs`, `browser_resize` | Page and tab control |
| `browser_close` | Close the browser and release the profile lock |

Additional tool groups are enabled with capabilities (section 7).

---

## 6. Profiles: persistence, privacy and locking

There are three modes:

| Mode | Flag | Behaviour |
|---|---|---|
| Persistent (default) | `--user-data-dir <directory>` | Logins, cookies and certificate trust survive restarts. Use this. |
| Isolated | `--isolated` | In-memory profile, discarded on close. For throwaway jobs and parallel sessions. |
| Storage state | `--storage-state <file.json>` | Loads cookies and local storage into an isolated context. |

### Privacy

`--browser chrome` uses the installed Chrome executable but a **different**
`--user-data-dir`. As a result:

- There is no Gmail, no bookmarks, no extensions and no saved password from your personal
  Chrome profile.
- Your personal Chrome can stay open at the same time, because a different profile means
  no lock.
- Never set `--user-data-dir` to `~/.config/google-chrome`. The agent would then see your
  real sessions, and the launch would fail while your browser is running.

### Locking

A profile directory can be held by **one** browser process at a time. Two OpenCode
sessions in two different folders that both use the same profile will conflict, and the
second one fails. Use a distinct `--user-data-dir` per project, or `--isolated` for the
extra one. Section 6.1 covers parallel use in detail.

### Where state lives

| Path | Contents | Rebuildable |
|---|---|---|
| `~/.cache/ms-playwright/` | Browser engines | Yes, by downloading again |
| `~/.cache/playwright-mcp/profile-*/` | Logins, cookies, certificate trust | **No. This is the only painful loss.** |
| `~/.cache/playwright-mcp/output/` | Screenshots, traces, page snapshots | Yes, disposable |
| `~/.npm/_npx/` | Cached npm package | Yes |
| Client configuration and instruction files | Server entries and rules | By hand, using this document |

Back up the configuration files and the `profile-*` directories, and the environment can
be rebuilt in minutes.

## 6.1 Running several agents at once

**For normal bug bounty and pentest work you do not need this.** A single agent is fully
supported and is the standard setup. The options below are needed only when two or more
agents browse at the same time.

| Situation | What happens | What to do |
|---|---|---|
| One agent, any folder | Works out of the box with the `playwright` entry | Nothing |
| Two or more agents in the same folder | They share one server process and one browser, so they interfere with each other's tabs and navigation | Use separate folders, or separate server entries |
| Two or more agents in different folders | Each starts its own server, both request the same profile, and the second one fails with a lock error | Give each one a different `--user-data-dir`, or enable `playwright-scratch` |

The three approaches:

| Need | Change |
|---|---|
| Unlimited parallel instances, no saved state, headless | Enable the `playwright-scratch` entry, which uses `--isolated` and `--headless` |
| Parallel agents that keep separate logins | A project-level `opencode.json` that overrides the `playwright` server with its own `--user-data-dir`. The project file replaces the whole server object, so repeat every flag. |
| One browser shared by several agents | HTTP transport: start `npx @playwright/mcp@latest --port 8931 --shared-browser-context` and connect clients with `type: "remote"` and `url: "http://127.0.0.1:8931/mcp"`. Rarely needed, because the agents share state and interfere. |

To reuse a login across parallel instances, export the session once with
`browser_storage_state`, then start the isolated instances with
`--storage-state <file>`.

Resource use: a headed Chrome instance takes roughly 500 MB of memory. Two to four
instances are comfortable on a machine with 16 GB.

---

## 7. Capabilities, browsers and context cost

`--caps` takes a comma-separated list. The `--help` text is out of date in version 0.0.83
and mentions only `vision,pdf,devtools`, but the server accepts all of the following,
verified with `tools/list`:

| Capability | Adds | Tools |
|---|---|---|
| none | Core automation | 25 |
| `network` | `browser_route`, `browser_route_list`, `browser_unroute`, `browser_network_state_set`. Request interception, mocking, offline mode. | +4 |
| `storage` | `browser_cookie_*`, `browser_localstorage_*`, `browser_sessionstorage_*`, `browser_storage_state`, `browser_set_storage_state` | +17 |
| `devtools` | Tracing, video, recording, highlight and annotate | +13 |
| `vision` | Coordinate-based mouse control. Requires a vision model. | +6 |
| `pdf` | PDF generation | +1 |
| `config` | `browser_get_config` | +1 |

Measured with `tools/list`: the core set has **25** tools, `--caps=network,storage` gives
**46**, and `--caps=network,storage,devtools` gives **59**.

Context cost is real. Every enabled server sends its whole tool catalogue to the model.
For security work, `--caps=network,storage` is the practical choice. Park browser entries
that you are not using by setting `"disabled": true`.

Browser selection:

| Goal | Flag | Download required |
|---|---|---|
| Bundled Chromium (default) | omit `--browser` | `playwright install chromium` |
| Installed Google Chrome | `--browser chrome` | No |
| Microsoft Edge | `--browser msedge` | Edge must be installed |
| Firefox | `--browser firefox` | `playwright install firefox` |
| WebKit, the Safari engine | `--browser webkit` | `playwright install webkit` plus dependencies |
| Any specific binary | `--executable-path /path/to/chrome` | The binary must exist |

Two traps:

- `--browser firefox` uses Playwright's patched Firefox build. A system Firefox is not
  compatible, so `--executable-path /usr/bin/firefox` fails.
- `--executable-path` pointed at a branded or patched build, such as Burp Suite's, is
  unreliable. Section 8.1 shows the measurement.

---

## 8. Burp Suite and ZAP integration

**You do not need Burp Suite's browser, and you do not need its extension.** What makes
"Burp's browser" work is two settings, both of which can be reproduced on Playwright's
browser:

| Burp Suite's embedded browser | Playwright equivalent |
|---|---|
| Proxy configured by Burp | `--proxy-server http://127.0.0.1:8080` |
| PortSwigger certificate trusted | `--ignore-https-errors`, or install the certificate (section 8.2) |
| Burp-owned and locked profile | Your own `--user-data-dir` |
| Cannot be automated | Fully automatable |

The result is identical interception in Proxy, HTTP history, Repeater and Intruder.

### 8.1 Why Burp Suite's own Chromium cannot be reused (measured)

The binary at `~/.BurpSuite/burpbrowser/<version>/chrome` reports
`Burp Browser 151.0.7922.137`.

| Test | Result |
|---|---|
| `Burp Browser --version` | Prints the version |
| `Burp Browser --headless --dump-dom about:blank` | Hung and was killed after 60 seconds, with no output |
| `/usr/bin/chromium` with the same command | Returned the DOM immediately |

It is patched to run under Burp's own launcher, its profile is locked while Burp is open,
and Burp upgrades change the version directory. Pointing `--executable-path` at it is
therefore unreliable. Do not do it.

The extension in `~/.BurpSuite/burp-chromium-extension` is equally unnecessary. It exists
so that Burp can drive the browser it launched itself. It also cannot be loaded reliably
any more: Chrome 137 and later removed `--load-extension` from branded builds, and
Playwright passes `--disable-extensions` by default.

### 8.2 Trust the certificate properly (optional)

```bash
sudo apt install -y libnss3-tools
# Burp must be running:
curl -s http://127.0.0.1:8080/cert -o /tmp/burp.der
certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n "PortSwigger CA" -i /tmp/burp.der
```

After that, `--ignore-https-errors` can be removed.

### 8.3 Configuration

Use a second server entry with its own profile rather than toggling flags on the default
entry:

```json
"playwright-burp": {
  "type": "local",
  "command": [
    "npx", "-y", "@playwright/mcp@latest",
    "--browser", "chrome",
    "--user-data-dir", "/home/USER/.cache/playwright-mcp/profile-burp",
    "--output-dir", "/home/USER/.cache/playwright-mcp/output",
    "--proxy-server", "http://127.0.0.1:8080",
    "--proxy-bypass", "localhost,127.0.0.1,::1",
    "--ignore-https-errors",
    "--timeout-action", "15000",
    "--timeout-navigation", "120000",
    "--console-level", "warning",
    "--idle-timeout", "1800000",
    "--caps", "network,storage"
  ],
  "timeout": { "startup": 120000, "execution": 1800000 }
}
```

A separate entry is important. If Burp is closed, every request through a proxied entry
fails with `ERR_PROXY_CONNECTION_FAILED`, which makes the agent look broken. Keep
`playwright` for direct traffic and enable `playwright-burp` only while testing. Toggling
means setting `"disabled": true` and saving the file, and OpenCode reloads automatically.

ZAP works the same way with `--proxy-server http://127.0.0.1:8080`. For mitmproxy, use
`--proxy-server http://127.0.0.1:8081`.

### 8.4 Flags that matter in security work

| Need | Flag |
|---|---|
| Intercept all traffic | `--proxy-server` |
| Broken or self-signed TLS | `--ignore-https-errors` |
| Keep credentials out of snapshots | `--secrets /path/to/secrets.env` in dotenv format; values are redacted |
| Evidence of a session | `--save-session`, and `--caps=devtools` for tracing and video |
| Where artefacts are written | `--output-dir ~/.cache/playwright-mcp/output` |
| Slow applications and single-page apps | `--timeout-action 15000 --timeout-navigation 120000` |
| Reduce JavaScript noise | `--console-level warning` |
| Close idle browsers automatically | `--idle-timeout 1800000` in milliseconds. Headed browsers otherwise never close. |

Do not enable `--block-service-workers` for application testing. It breaks many
single-page applications.

---

## 9. Reference configuration

The configuration produced by `setup.sh` contains these entries:

| Server | State | Purpose |
|---|---|---|
| `playwright` | enabled | System Chrome, persistent profile, direct traffic |
| `playwright-burp` | enabled | Same browser, all traffic through the local proxy |
| `playwright-scratch` | disabled | Isolated, headless, no saved state. For parallel agents. |
| `playwright-chromium` | disabled | Bundled Chromium fallback |
| `playwright-firefox` | disabled | Second browser engine |

The parked entries exist because a Chrome update can occasionally outrun the bundled
Playwright build. Changing `disabled` to `false` is the immediate workaround.

---

## 10. Installing a second engine

```bash
npx -y playwright@latest install webkit        # only if you really need the Safari engine
sudo npx playwright install-deps webkit        # may fail on Kali, use apt instead (section 12)
```

To add another entry, copy the `playwright` block, change `--browser`, and give it a new
`--user-data-dir`.

---

## 11. Verify

The repository ships a health check that covers every item below:

```bash
./verify.sh
```

Manual checks:

```bash
# The server is reachable and configured. Run from a folder OpenCode has opened before.
opencode mcp list                 # expected: playwright connected

# The package itself runs.
npx -y @playwright/mcp@latest --version

# The engines are present.
ls ~/.cache/ms-playwright/

# Headed mode needs a display.
echo $DISPLAY                     # for example :0
```

Smoke test in the agent:

> Use playwright to open https://demo.playwright.dev/todomvc, add two tasks, and verify
> that both are present.

Burp smoke test, with Burp listening on port 8080 and `playwright-burp` enabled:

> Open https://example.com through playwright-burp, then read the request from Burp's proxy
> history.

A direct protocol probe that needs no client, useful when a client misbehaves:

```bash
(printf '%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' \
 '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
 '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'; sleep 8) \
| npx -y @playwright/mcp@latest --headless --isolated
```

A JSON response containing a `tools` array means the server is healthy and the problem is
in the client.

---

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `opencode mcp list` prints `No MCP servers configured` even though the configuration is correct | The folder has not been opened in OpenCode before, so the command has no location context for it | Run `./verify.sh`, which reads the configuration file directly, or open OpenCode in that folder once |
| `No MCP servers configured` and the configuration really is missing | The entry is absent, or the JSON is invalid | Validate with `python3 -m json.tool opencode.json` |
| `EndOfFileExpected` or `is not valid JSON(C)` | Two top-level JSON objects were pasted into one file | Merge them into a single object |
| The server is configured but no tools appear | Version 1 syntax was used, for example `mcp.playwright` or `"enabled": true` | Use `mcp.servers` with `type: "local"` |
| The server is connected but the agent never uses it | No instruction tells the agent to use it | Add the rules from section 4.5 |
| The first call takes about 20 seconds | `npx` is populating its cache | Run `npx -y @playwright/mcp@latest --version` once |
| The server does not start | Node or npx is missing or too old | Check `node -v` for version 20 or newer |
| `No such file` for `.../chrome-linux/chrome` | Wrong directory name | It is `chrome-linux64` |
| `error while loading shared libraries` | Missing system libraries | `sudo apt install -y libnss3 libatk-bridge2.0-0 libgbm1 libasound2t64 libxkbcommon0 libgtk-3-0`, or `libasound2` on older releases |
| `playwright install-deps` fails | It resolves Ubuntu package names on Kali | Skip it and install the libraries listed above |
| The browser does not open in headed mode | No display is available | Check `echo $DISPLAY`, or use a headless entry |
| `Target page, context or browser has been closed` | Another process holds the profile | One browser per profile; use a different `--user-data-dir` or `--isolated` |
| `ERR_PROXY_CONNECTION_FAILED` | Burp or ZAP is not listening | Start the proxy, or use the non-proxied `playwright` entry |
| `net::ERR_CERT_AUTHORITY_INVALID` | The Burp certificate is not trusted | Use `--ignore-https-errors`, or install the certificate (section 8.2) |
| Element references are stale and clicks miss | The agent acted on an old snapshot | Take a new snapshot before acting |
| The snapshot is empty or incomplete | The page has not finished loading | Use `browser_wait_for`, then snapshot again |
| A CAPTCHA or bot wall appears | The automation fingerprint was detected | Try `--browser chrome`, or solve it manually in the visible window |
| A `--caps` value seems to be ignored | The `--help` text is out of date | `network`, `storage`, `devtools`, `vision`, `pdf` and `config` are all valid |
| Firefox does not start | The system Firefox is not Playwright's build | Run `playwright install firefox` and remove `--executable-path` |
| The tools consume too much context | Too many servers or capabilities are enabled | Park entries with `"disabled": true` and reduce `--caps` |

Logs are in `~/.local/share/opencode/log/opencode.log` for OpenCode. For any other client,
run the protocol probe in section 11 to see the server's own error output.

---

## 13. What the widely shared guides get wrong

These mistakes are common in documents that circulate online. They are listed here so that
nobody reintroduces them.

| Claim | Reality |
|---|---|
| `"mcpServers": { ... }` configures OpenCode | That is the Claude Desktop and generic MCP format. OpenCode version 2 uses `mcp.servers` with `type: "local"` and a `command` array. |
| `"mcp": { "playwright": { ... }, "enabled": true }` | Version 1 syntax, silently ignored by version 2. Use `mcp.servers` and `disabled`. |
| `--executable-path` pointed at Playwright's own Chromium | Pointless, because that is already the default. |
| `--no-sandbox` in the configuration | Only needed when running as root or inside a container. On a normal desktop it weakens the sandbox for no benefit. |
| Install the Python `playwright` package | Not required for MCP. It is only needed to write your own Python scripts. |
| `playwright install-deps` as a setup step | Fails on Kali. Install the specific libraries instead. |
| Burp Suite's Chromium can be driven with `--executable-path` | Measured: it hangs when launched outside Burp (section 8.1). |
| A Burp extension is required for proxying | No. Proxy settings plus certificate trust are sufficient, and the extension no longer loads reliably. |
| Nothing about profiles | A persistent profile, and one browser per profile, prevents the most common failure. |
| Nothing about `--caps` | The default set is only 25 tools, and `network` and `storage` matter a great deal in security work. |

---

## 14. Update, back up, rebuild and uninstall

**Update.** The package is resolved from `@latest` on every start, so no update step is
normally required. For reproducibility, pin the version in the command line, for example
`@playwright/mcp@0.0.83`. Refresh the browser engines after a Playwright upgrade:

```bash
npx -y playwright@latest install chromium firefox
```

**Back up** the parts that cannot be recreated:

```bash
tar czf ~/playwright-mcp-backup.tgz \
  ~/.config/opencode/opencode.json \
  ~/.config/opencode/AGENTS.md \
  ~/.cache/playwright-mcp/profile-chrome \
  ~/.cache/playwright-mcp/profile-burp
```

**Rebuild on a fresh machine.** The fastest path is to clone this repository and run the
installer, which performs the steps below and updates the configuration:

```bash
./setup.sh
./verify.sh
```

The equivalent manual steps are:

```bash
npx -y playwright@latest install chromium firefox
mkdir -p ~/.cache/playwright-mcp/{profile-chrome,profile-burp,profile-scratch,profile-chromium,profile-firefox,output,output-scratch}
tar xzf ~/playwright-mcp-backup.tgz -C /
```

**Uninstall.**

```bash
# 1. Remove the server entries from the client configuration.
# 2. Remove the engines and the profiles:
rm -rf ~/.cache/ms-playwright ~/.cache/playwright-mcp

# 3. Optionally clear the npm cache:
npm cache clean --force
```

For other clients, use `claude mcp remove playwright`, `codex mcp remove playwright`, or
delete the `mcpServers` entry.

Removing the profiles also removes every saved login for the agent's browser. The personal
browser profile is never touched by this setup.

---

## 15. References

- Playwright MCP: <https://github.com/microsoft/playwright-mcp>
- Installation: <https://playwright.dev/mcp/installation>
- Introduction: <https://playwright.dev/mcp/introduction>
- Browser support: <https://playwright.dev/docs/browsers>
- Authentication and storage state: <https://playwright.dev/docs/auth>
- Model Context Protocol: <https://modelcontextprotocol.io/>
- OpenCode MCP servers: <https://opencode.ai/v2/docs/mcp-servers>
