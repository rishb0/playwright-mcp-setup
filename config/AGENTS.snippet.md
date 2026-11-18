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
