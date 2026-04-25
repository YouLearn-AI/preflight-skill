# preflight-skill

Public Claude Code skill + installer for **preflight** — agent-driven QA testing for shipped Electron desktop apps. Ships the agent skill plus the binary install path. Source code stays private.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/YouLearn-AI/preflight-skill/main/install.sh | bash
```

Requires:
- macOS
- `gh auth login` to a GitHub account with read access to `YouLearn-AI/homebrew-preflight`
- macOS Privacy permissions (Accessibility, Screen Recording, Mic, Input Monitoring) — installer walks you through

## What you get

- `preflight` CLI on your PATH (`preflight smoke`, `preflight run <id>`, `preflight doctor`).
- Claude Code skill at `~/.claude/skills/preflight/SKILL.md` — your Cursor/Claude Code session auto-picks it up. Ask "run preflight" or "is this safe to ship" and the agent knows what to do.
- System deps installed (audiokit, cua-driver, BlackHole 2ch, ffmpeg, tesseract).

## Usage

In Cursor or Claude Code:

> "Run preflight smoke and tell me if anything regressed"

Or directly:

```bash
preflight smoke                       # fast subset, <30s
preflight run voiceos.bg-dictation-no-foreground-steal
preflight list                        # all journeys
preflight doctor                      # health check
```

## License

MIT for the skill + installer. The preflight binary itself is proprietary (YouLearn-AI).
