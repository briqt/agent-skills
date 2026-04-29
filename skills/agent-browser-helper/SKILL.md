---
name: agent-browser-helper
description: "Local Chrome lifecycle management with anti-detection for agent-browser. Start/stop a stealth Chrome instance with persistent profiles, then connect agent-browser via CDP. Use when you need to browse sites with bot detection (login flows, scraping), maintain persistent login sessions across runs, or manage multiple browser profiles. Triggers: start browser, stealth chrome, anti-detection, persistent login, browser profile, connect CDP."
---

# agent-browser-helper

Manages a local Chrome instance with anti-detection parameters and persistent
profiles. Designed as a companion to the `agent-browser` skill — this skill
starts Chrome, agent-browser operates it.

## Prerequisites

- `agent-browser` skill installed: `npx skills add vercel-labs/agent-browser@agent-browser -g -y`
- `agent-browser` CLI installed: `npm i -g agent-browser && agent-browser install`
- Google Chrome or Chromium installed

## Quick start

```bash
# 1. Start stealth Chrome with persistent profile
bash $SCRIPTS/chrome.sh start

# 2. Use agent-browser with CDP connection
agent-browser open https://example.com --cdp 9222
agent-browser snapshot -i
agent-browser click @e1

# 3. Stop when done (or keep running for session reuse)
bash $SCRIPTS/chrome.sh stop
```

## Commands

> `$SCRIPTS` = this skill's `scripts/` absolute path.

### start — Launch anti-detection Chrome

```bash
bash $SCRIPTS/chrome.sh start                    # default profile, port 9222
bash $SCRIPTS/chrome.sh start --profile work     # named profile
bash $SCRIPTS/chrome.sh start --headless         # headless mode
bash $SCRIPTS/chrome.sh start --port 9333        # custom CDP port
```

### stop — Graceful shutdown

```bash
bash $SCRIPTS/chrome.sh stop
bash $SCRIPTS/chrome.sh stop --profile work
```

### status — Check if Chrome is running

```bash
bash $SCRIPTS/chrome.sh status
```

## Configuration

Edit `config.json` in the skill directory:

```json
{
  "browser": {
    "headless": false,
    "noSandbox": true,
    "defaultProfile": "default",
    "extraArgs": [
      "--disable-blink-features=AutomationControlled"
    ],
    "profiles": {
      "default": { "cdpPort": 9222 }
    }
  }
}
```

### Optional profile settings

| Field | Description | Default |
|-------|-------------|---------|
| `cdpPort` | CDP debugging port | 9222 |
| `userDataDir` | Custom user data directory (reuse existing login state) | `~/.agent-browser-helper/{profile}/user-data` |

### extraArgs examples

| Arg | Purpose |
|-----|---------|
| `--disable-blink-features=AutomationControlled` | Hide automation (enabled by default) |
| `--proxy-server=http://HOST:PORT` | HTTP proxy |
| `--lang=zh-CN` | Browser language |
| `--window-size=1920,1080` | Window size |
| `--user-agent=...` | Custom User-Agent |

## Anti-detection features

- No `--enable-automation` flag (navigator.webdriver stays undefined)
- `--disable-blink-features=AutomationControlled` by default
- Persistent user-data-dir (real cookies, extensions, history)
- Minimal launch parameters (looks like a normal Chrome)
- No Playwright/Puppeteer dependency in the launch path

## Using with agent-browser

After `chrome.sh start`, agent-browser connects via CDP:

```bash
agent-browser open <url> --cdp 9222
agent-browser snapshot -i
agent-browser fill @e1 "username"
agent-browser click @e2
agent-browser screenshot result.png
```

All agent-browser commands work — click, fill, type, wait, screenshot,
network, cookies, state save/load, etc. See `agent-browser skills get core`
for the full reference.

## Notes

- User data persists at `~/.agent-browser-helper/{profile}/user-data`
- Login state survives across sessions (no need to re-login)
- Multiple profiles supported on different ports
- Chrome process tracked via PID file at `~/.agent-browser-helper/{profile}/chrome.pid`
