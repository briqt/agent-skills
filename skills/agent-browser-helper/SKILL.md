---
name: agent-browser-helper
description: "Local Chrome lifecycle management with anti-detection for agent-browser. Start/stop a stealth Chrome instance with persistent profiles, then connect agent-browser via CDP. Use when you need to browse sites with bot detection (login flows, scraping), maintain persistent login sessions across runs, or manage multiple browser profiles. Triggers: start browser, stealth chrome, anti-detection, persistent login, browser profile, connect CDP."
---

# agent-browser-helper

Manages a local Chrome instance with anti-detection parameters and persistent
profiles. After starting Chrome, use the **agent-browser** skill to operate it.

## Prerequisites

- **agent-browser** skill: `npx skills add vercel-labs/agent-browser@agent-browser -g -y`
- **agent-browser** CLI: `npm i -g agent-browser && agent-browser install`
- Google Chrome or Chromium installed

If agent-browser is not installed, prompt the user to install it before proceeding.

## Usage

> `$SCRIPTS` = this skill's `scripts/` absolute path.

### start — Launch anti-detection Chrome

```bash
bash $SCRIPTS/chrome.sh start                    # default profile, port 9222
bash $SCRIPTS/chrome.sh start --profile work     # named profile
bash $SCRIPTS/chrome.sh start --headless         # headless mode
bash $SCRIPTS/chrome.sh start --port 9333        # custom CDP port
```

Output: `{"status":"started","pid":12345,"cdpPort":9222,"profile":"default"}`

### stop — Graceful shutdown

```bash
bash $SCRIPTS/chrome.sh stop
bash $SCRIPTS/chrome.sh stop --profile work
```

### status — Check if Chrome is running

```bash
bash $SCRIPTS/chrome.sh status
```

## After starting Chrome

Use the **agent-browser** skill with `--cdp <port>` to connect and operate
the browser. Refer to agent-browser's own skill documentation for all
available commands (`agent-browser skills get core`).

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

### Profile options

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

## Why this skill exists

- No `--enable-automation` flag (`navigator.webdriver` stays undefined)
- Persistent user-data-dir (real cookies, extensions, history survive restarts)
- Minimal launch parameters (looks like a normal user's Chrome)
- No Playwright/Puppeteer in the launch path — pure Chrome + CDP port
- Multiple profiles on different ports, isolated from each other
