# Playwright MCP Setup

A tested, practical guide and installer that gives any AI agent a real browser.

Configure it once and your agent can log in, click, fill forms, read pages, take
screenshots, inspect network traffic and intercept requests, without wasting turns
trying to find or launch a browser by itself.

The setup is designed for security work. It includes a direct browser for
reconnaissance and a second, separate browser that sends every request through
Burp Suite or ZAP.

---

## Table of contents

1. [What this is](#1-what-this-is)
2. [What this is not](#2-what-this-is-not)
3. [Requirements](#3-requirements)
4. [Quick start](#4-quick-start)
5. [Prompt for your AI agent](#5-prompt-for-your-ai-agent)
6. [What gets installed](#6-what-gets-installed)
7. [How it works](#7-how-it-works)
8. [Using the browser in real work](#8-using-the-browser-in-real-work)
9. [Configuration reference](#9-configuration-reference)
10. [Troubleshooting](#10-troubleshooting)
11. [Uninstall](#11-uninstall)
12. [Credits and license](#12-credits-and-license)

---

## 1. What this is

This repository contains three things:

| File | Purpose |
|---|---|
| `PLAYWRIGHT-MCP-SETUP.md` | The complete guide. Requirements, installation, configuration for every major client, profiles, Burp Suite integration, capabilities, troubleshooting, and what other guides get wrong. |
| `setup.sh` | An installer that performs the whole setup safely and can be run again at any time. |
| `verify.sh` | A health check that tells you exactly what is missing or misconfigured. |

It configures [Microsoft's Playwright MCP server](https://github.com/microsoft/playwright-mcp)
for AI clients such as OpenCode, Claude Code, Codex, Cursor, VS Code and Claude
Desktop. The server itself is downloaded and maintained by Microsoft. This
repository does not contain or modify it.

The guide is based on measurements taken on a real machine, not on assumptions. It
documents the failures that most published guides do not mention, including the
OpenCode version 2 configuration format, the browser profile lock, and why Burp
Suite's own Chromium build cannot be reused.

## 2. What this is not

- It is not a fork of Playwright MCP and it is not affiliated with Microsoft.
- It is not a replacement for the official documentation. It is a practical,
  opinionated setup that has been tested end to end.
- It is not a security boundary. Playwright MCP drives a real browser with your
  permissions. Only point it at systems you are authorised to test.

## 3. Requirements

| Requirement | Details |
|---|---|
| Node.js 20 or newer | Includes `npx`. Check with `node -v`. |
| `python3` | Used by `setup.sh` to edit JSON configuration without breaking it. |
| An MCP-capable client | OpenCode, Claude Code, Codex, Cursor, VS Code, Claude Desktop, or similar. |
| A desktop session for visible browsers | Check `echo $DISPLAY`. Not required for headless entries. |
| Network access, once | Roughly one gigabyte of browser engines on the first run. |

Optional but recommended for security work:

| Requirement | Details |
|---|---|
| Burp Suite or ZAP | Needed only for the proxied server entry. |
| Google Chrome | Used by default because its fingerprint looks like a normal browser. |

## 4. Quick start

```bash
git clone https://github.com/rishb0/playwright-mcp-setup.git
cd playwright-mcp-setup
chmod +x setup.sh verify.sh
./setup.sh
./verify.sh
```

Then, from a project folder, confirm that your client can see the server:

```bash
opencode mcp list
```

You should see `playwright` and `playwright-burp` marked as connected, and the
optional servers marked as disabled.

If the command prints `No MCP servers configured`, you are in a folder that OpenCode
has not opened before. Open OpenCode in that folder once, or simply run `./verify.sh`,
which reads the configuration file directly and does not depend on the current folder.

If you prefer to see the plan before anything changes:

```bash
./setup.sh --dry-run
```

## 5. Prompt for your AI agent

The point of this repository is that you do not have to type the commands yourself.
Open your agent inside this folder and paste one of the prompts below.

### 5.1 Install everything

```text
Read PLAYWRIGHT-MCP-SETUP.md in this folder. Then run ./setup.sh and ./verify.sh,
fix anything that verify.sh reports as FAIL, and show me the output of
opencode mcp list at the end. Do not install the Python Playwright package and do
not use sudo.
```

### 5.2 Check an existing installation

```text
Run ./verify.sh in this folder and explain every FAIL and WARN in plain language.
Fix what you can without using sudo, then run it again.
```

### 5.3 Prove that the browser works

```text
Use the playwright tools to open https://demo.playwright.dev/todomvc, add two tasks,
take a snapshot, and confirm that both tasks are present. Report the page title and
the snapshot result.
```

### 5.4 Route traffic through Burp Suite

```text
Burp Suite is running on 127.0.0.1:8080. Enable the playwright-burp server, open
https://example.com through it, and read the request from Burp's proxy history to
confirm that the traffic is being intercepted.
```

### 5.5 Typical bug bounty request

```text
Use the playwright tools to open the target, log in with the credentials in .env,
map every page reachable from the dashboard, and list the forms, API calls and
parameters you find. Take a snapshot after each navigation and do not guess element
references.
```

More prompts, including pentest and reporting examples, are in
[section 8](#8-using-the-browser-in-real-work).

## 6. What gets installed

`setup.sh` adds five server entries. Only two are enabled by default, because every
enabled server adds its tools to the model's context.

| Server | State | Purpose |
|---|---|---|
| `playwright` | enabled | System Google Chrome, persistent profile, direct traffic. The default choice. |
| `playwright-burp` | enabled | The same browser, but every request goes through a local proxy such as Burp Suite or ZAP. |
| `playwright-scratch` | disabled | Isolated, headless, no saved state. Use it when several agents must browse at the same time. |
| `playwright-chromium` | disabled | Playwright's bundled Chromium. A fallback if a Chrome update ever breaks the default entry. |
| `playwright-firefox` | disabled | Firefox. Enable it when a target behaves differently in a second browser engine. |

It also creates these directories:

| Path | Purpose |
|---|---|
| `~/.cache/ms-playwright/` | Browser engines downloaded by Playwright. |
| `~/.cache/playwright-mcp/profile-chrome/` | Persistent profile for the direct browser, including logins and cookies. |
| `~/.cache/playwright-mcp/profile-burp/` | Separate persistent profile for proxied traffic. |
| `~/.cache/playwright-mcp/output/` | Screenshots, traces and page snapshots. |

The installer never overwrites an existing server entry unless you pass `--force`,
and it always writes a timestamped backup before editing a file.

## 7. How it works

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

The agent works in a loop. It navigates, receives an accessibility snapshot of the
page, chooses an element from that snapshot, acts on it, and then takes another
snapshot to confirm the result. This is why the tools are reliable without any
computer vision: the page is described as structured data, not as pixels.

Two details matter in practice:

- **Profiles are locked.** A browser profile directory can only be used by one
  browser process at a time. Two agents in different folders that share the same
  profile will conflict. The `playwright-scratch` entry exists to avoid this.
- **A dead proxy looks like a broken browser.** If Burp Suite is not running, every
  request through `playwright-burp` fails. This is why the proxied server is a
  separate entry and not a setting on the default one.

## 8. Using the browser in real work

### 8.1 Reconnaissance and mapping

```text
Open the target with playwright and map the application. For every page you reach,
report the URL, the visible headings, the forms and their fields, and the network
requests that were made. Do not submit any form yet.
```

### 8.2 Authenticated testing

```text
Log in with the credentials in .env. Then repeat the same request as a lower
privileged account and tell me whether the response differs. Use
browser_network_requests to show the exact calls.
```

### 8.3 Request interception

The `network` capability is enabled, so the agent can rewrite or block requests:

```text
Use browser_route to intercept requests to /api/ and log every request body. Do not
modify anything yet.
```

### 8.4 Evidence collection

```text
Take a screenshot of the vulnerable page, save the storage state, and export the
network log. Name the files after the finding identifier.
```

### 8.5 Parallel agents

One agent at a time is the normal setup and needs no extra work. If you want two or
more agents browsing at the same time, read section 6.1 of
`PLAYWRIGHT-MCP-SETUP.md`. In short, enable `playwright-scratch` or give each project
its own profile directory.

## 9. Configuration reference

The generated configuration is in `config/`:

| File | Use it for |
|---|---|
| `config/opencode.json.example` | OpenCode version 2, which uses `mcp.servers` and `type: "local"`. |
| `config/mcpServers.example.json` | Claude Desktop, Cursor, VS Code and other clients that use a `mcpServers` map. |
| `config/AGENTS.snippet.md` | The browser rules to paste into your global agent instructions. |

Replace `YOUR_USERNAME` with your actual home directory name before using an example
file directly. `setup.sh` does this for you automatically.

Client-specific commands:

```bash
# OpenCode
opencode mcp add playwright --global -- npx -y @playwright/mcp@latest --browser chrome

# Claude Code
claude mcp add playwright -- npx -y @playwright/mcp@latest --browser chrome

# Codex
codex mcp add playwright -- npx -y "@playwright/mcp@latest" --browser chrome
```

The complete list of options, including proxies, profiles, capabilities, timeouts
and browser selection, is in `PLAYWRIGHT-MCP-SETUP.md`.

## 10. Troubleshooting

Run `./verify.sh` first. It detects most of the problems below and tells you which
one applies.

| Symptom | Likely cause | Fix |
|---|---|---|
| `No MCP servers configured` | The folder has not been opened in OpenCode before, or the configuration is invalid | Run `./verify.sh`, or open OpenCode in that folder once |
| The server is configured but the agent never uses it | No instruction tells the agent to use it | Add the rules from `config/AGENTS.snippet.md` to your global instructions |
| `ERR_PROXY_CONNECTION_FAILED` | Burp Suite or ZAP is not running | Start the proxy, or use the `playwright` entry instead |
| Profile lock error | Another browser is using the same profile directory | Use a different profile, or enable `playwright-scratch` |
| Clicks miss their target | The agent acted on an old snapshot | Ask it to take a fresh snapshot before acting |
| Browser does not open | No graphical session is available | Check `echo $DISPLAY`, or use a headless entry |
| The first call is very slow | `npx` is downloading the package for the first time | Run `npx -y @playwright/mcp@latest --version` once |

The full troubleshooting table, with more than twenty entries, is in section 12 of
`PLAYWRIGHT-MCP-SETUP.md`.

## 11. Uninstall

```bash
# 1. Remove the server entries from your client configuration.
# 2. Remove the browser engines and profiles:
rm -rf ~/.cache/ms-playwright ~/.cache/playwright-mcp

# 3. Optionally clear the npm cache:
npm cache clean --force
```

Removing the profiles also removes every saved login for the agent's browser. Your
personal browser profile is never touched by this setup.

## 12. Credits and license

- Playwright MCP is developed and maintained by Microsoft:
  <https://github.com/microsoft/playwright-mcp>
- Playwright is developed by Microsoft: <https://playwright.dev>
- Model Context Protocol: <https://modelcontextprotocol.io>

This repository contains only original documentation and scripts. It is not
affiliated with, endorsed by, or supported by Microsoft.

Released under the MIT License. See [LICENSE](LICENSE).
