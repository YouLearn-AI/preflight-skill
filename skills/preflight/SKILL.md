---
name: preflight
description: Run pre-release QA flows for the customer's app — dictation, agent mode, settings, onboarding. Use when the user asks "run preflight", "QA before push", "smoke test", "is this safe to ship", "check dictation flows", or any pre-release verification ask. Background-only — never disturbs the user's foreground app.
---

# preflight skill

Full agent instructions: **[`AGENTS.md`](../../AGENTS.md)** in this repo.

That covers:
- CLI surface (`run`, `smoke`, `list`, `doctor`, `verdict`)
- When-user-asks-X-run-Y mapping
- Architecture (audiokit + skipPaste CDP + cua AX, all BG)
- Hotkey bindings (ctrl+shift+d for dictation, ctrl+option+a for agent, push-to-talk only)
- Verification surfaces (DB / log / target-app body)
- Anti-patterns (don't osascript keystroke, don't open -a, don't asar-patch)
- Reporting format

Single source of truth is AGENTS.md — this file just gives Claude Code a description matcher.
