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

**IMPORTANT:** The agent-browser **skill** must be installed for the AI agent
to know how to operate the browser. Without it, the agent has no command
reference and will guess incorrectly. Check `chrome.sh start` output — if it
shows a warning about missing skill, install it first.

## Workflow

### Step 1: Start Chrome

```bash
bash $SCRIPTS/chrome.sh start
```

Output example:
```json
{"status":"started","pid":12345,"cdpPort":9222,"profile":"default","userDataDir":"~/.agent-browser-helper/default/user-data"}
```

**Read the output carefully** — it tells you the CDP port and which profile
is active. The profile's user-data-dir persists login state across sessions.

### Step 2: Load agent-browser documentation

**MUST DO before running any agent-browser command.** Run:

```bash
agent-browser skills get core
```

This outputs the correct command syntax. Do NOT guess commands — they use
non-standard conventions (e.g., `open` not `navigate`, positional args not
`--url` flags). If this command fails, the CLI is not installed.

### Step 3: Operate via agent-browser

Connect using the CDP port from Step 1:

```bash
agent-browser open <url> --cdp 9222
```

All subsequent commands in the same session inherit the CDP connection.

## Commands

> `$SCRIPTS` = this skill's `scripts/` absolute path.

### start

```bash
bash $SCRIPTS/chrome.sh start                    # default profile, headed, port 9222
bash $SCRIPTS/chrome.sh start --profile work     # named profile (isolated user-data)
bash $SCRIPTS/chrome.sh start --headless         # headless (default is HEADED)
bash $SCRIPTS/chrome.sh start --port 9333        # custom CDP port
```

### stop

```bash
bash $SCRIPTS/chrome.sh stop
bash $SCRIPTS/chrome.sh stop --profile work
```

### status

```bash
bash $SCRIPTS/chrome.sh status
```

## Profile system

Each profile has its own isolated user-data directory:
`~/.agent-browser-helper/{profile}/user-data`

This means:
- **Cookies, localStorage, sessions persist** across browser restarts
- **Extensions** installed in a profile stay installed
- **Login state survives** — no need to re-authenticate every time
- Different profiles are fully isolated (different ports, different data)

**When to use named profiles:**
- `--profile xiaohongshu` — keep XHS login separate
- `--profile work` — corporate SSO sessions
- `--profile clean` — fresh profile for testing

**Important:** If the user has previously logged into a site, remind them
which profile contains that session. Don't start a new unnamed profile and
lose their login state.

## Configuration

Edit `config.json` in the skill directory:

```json
{
  "browser": {
    "headless": false,
    "noSandbox": true,
    "defaultProfile": "default",
    "extraArgs": [
      "--disable-blink-features=AutomationControlled",
      "--disable-infobars",
      "--window-size=1280,720"
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
| `userDataDir` | Custom user data directory | `~/.agent-browser-helper/{profile}/user-data` |

### extraArgs for anti-detection

| Arg | Purpose | Default |
|-----|---------|---------|
| `--disable-blink-features=AutomationControlled` | Hide `navigator.webdriver` | ✅ on |
| `--disable-infobars` | Remove automation info bar | ✅ on |
| `--window-size=1280,720` | Normal viewport (avoids 800x600 fingerprint) | ✅ on |
| `--proxy-server=http://HOST:PORT` | HTTP proxy | off |
| `--lang=zh-CN` | Browser language | off |
| `--user-agent=...` | Custom User-Agent | off |

## Anti-detection defaults

Out of the box, this skill applies:

1. **No `--enable-automation`** — `navigator.webdriver` returns `undefined`
2. **`--disable-blink-features=AutomationControlled`** — removes CDP automation markers
3. **`--disable-infobars`** — no "Chrome is being controlled" banner
4. **`--window-size=1280,720`** — normal desktop viewport
5. **Headed mode** — headless browsers have distinct fingerprints
6. **Persistent profile** — real cookies/history make the browser look "lived-in"
7. **No Playwright/Puppeteer in launch path** — no extra automation flags injected

For sites with aggressive detection (Cloudflare, DataDome), consider also adding
a real User-Agent string and proxy to `extraArgs`.
