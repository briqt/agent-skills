# agent-skills

AI agent skills maintained by [@briqt](https://github.com/briqt).

## Skills

| Skill | Description |
|-------|-------------|
| [agent-browser-helper](skills/agent-browser-helper/) | Local Chrome lifecycle with anti-detection, persistent profiles. Companion to [agent-browser](https://github.com/vercel-labs/agent-browser). |
| [pty-bridge](skills/pty-bridge/) | Interactive terminal session management (SSH, REPLs, databases, TUI apps) via PTY. |
| [wecom-smartsheet](skills/wecom-smartsheet/) | Read WeCom smart sheet data via browser JS memory reverse-engineering. |
| [wecom-smartsheet-api](skills/wecom-smartsheet-api/) | Read WeCom smart sheet data via backend HTTP API. |

## Installation

```bash
# Install all skills
npx skills add briqt/agent-skills -g --all

# Install a specific skill
npx skills add briqt/agent-skills -g -s agent-browser-helper
npx skills add briqt/agent-skills -g -s pty-bridge
npx skills add briqt/agent-skills -g -s wecom-smartsheet
```

## License

MIT
