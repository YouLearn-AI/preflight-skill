# preflight — agent guide

Canonical agent-facing instructions for [preflight](https://github.com/YouLearn-AI/preflight-skill). Named [`AGENTS.md`](https://agents.md/) so any agent (Claude Code, Cursor, Codex, etc.) picks it up. Same content is exposed as a Claude Code skill at `skills/preflight/SKILL.md`.

## What preflight is

End-to-end regression testing for shipped Electron desktop apps on macOS. Drives the binary through real audio + accessibility primitives, captures verdicts, surfaces regressions. Currently configured for VoiceOS (a dictation app).

## Core CLI surface

```bash
preflight list                         # show all registered journeys
preflight smoke                        # fast subset, <30s
preflight run <journey-id>             # run one journey end-to-end (JSON to stdout)
preflight doctor                       # health check (deps + permissions)
preflight doctor --install-missing     # install missing brew deps + open Privacy panes
preflight verdict <runId>              # query past run verdict
```

All commands emit JSON with `verdict` ∈ `{pass, fail, error}`. Exit 0 = pass.

## When user asks X, run Y

| User says | Run |
|---|---|
| "run preflight" / "smoke" / "is this safe to push" | `preflight smoke` |
| "what flows can be tested" | `preflight list` |
| "test dictation" | `preflight run voiceos.bg-dictation-no-foreground-steal` |
| "test agent mode" | `preflight run voiceos.agent-query-slack-last-message` |
| "test grammar / multi-sentence" | `preflight run voiceos.dictate-slack-en-grammar` |
| "walk through the UI" | `preflight run voiceos.bg-cursor-walk-voiceos-nav` |
| "is the env set up" | `preflight doctor` |
| "fix missing deps" | `preflight doctor --install-missing` |

## Architecture (what your invocations do)

### Dictation pipeline

- **Hotkey**: ctrl+shift+d (LEFT mods) — push-to-talk hold (tap-tap toggles silently lose data; always hold).
- **CDP IPC equivalent**: `window.api.pill.startDictation({skipPaste: true})` over `localhost:9222`. Pair with `pill.stopRecording()`.
- **`skipPaste: true`** is the BG-mode flag. With it, VoiceOS records + transcribes + writes a DB row but does NOT auto-paste — keeps tests fully background.
- **Audio injection**: `audiokit inject device <wav> --set-input` plays through BlackHole 2ch (virtual mic). VoiceOS reads it as real input.

### Agent mode pipeline

- **Hotkey**: ctrl+option+a (LEFT mods) — push-to-talk hold.
- Agent flow: record → transcribe → server-side reasoning + tool calls (Slack, Calendar, etc.) → response stream → done.
- Status codes in log: `0` (transcribing), `1` (transcript ready), `3` (tool invocation), `4` (tool result), `5` (response stream), `7` (done).

### Target-app interactions (always BG via cua)

- **`cua-driver` daemon** must be running.
- **AX-mode**: `cua click` / `set_value` — no focus theft, pure background.
- **Pixel-mode click** (real CGEvent mouse): brings target window to front. Use only when testing the real-mouse code path.
- **For typing**: prefer `set_value` over `type_text_chars` for Slack / Discord (their WebViews drop chars from per-char CGEvent posting).
- **Hotkeys / single keys**: use cua's `hotkey` / `press_key` (postToPid, BG) — not `osascript keystroke`.

## Verification surfaces

- **App DB**: VoiceOS has a sqlite DB at `~/Library/Application Support/VoiceOS/voiceos.db`. DB delta cross-check is highest-signal — catches silent data loss bugs.
- **App log**: `~/Library/Logs/VoiceOS/main.log`.
- **Target-app body**:
  - Notes: `osascript -e 'tell application "Notes" to body of note 1'` (Scripting Bridge, BG, reliable for multi-line).
  - Slack / Electron: `cua get_window_state` parsed AX tree.
- **Frontmost**: `cua list_apps` — verify it never changed during the run.

## Reading results

```jsonc
{
  "verdict": "pass" | "fail" | "error",
  "errors": [{"code": "...", "message": "..."}],
  "latency": {
    "spans": {...},
    "budget": {"met": true, "maxMs": 30000}
  }
}
```

Don't trust verdict alone. Always inspect `errors[]` AND `latency.budget.met`.

## Anti-patterns — DO NOT do these

- Don't modify the customer's app bundle (signature breaks).
- Don't `osascript keystroke` to drive target apps (needs frontmost). Use cua's BG primitives.
- Don't relaunch the target app via `open -a` (activates). Use `open -ga --args ...`.
- Don't trust verdict=`pass` blindly — check `errors[]` and budget.

## Reporting format

```
preflight smoke — N journeys, M failed in Ts

PASS: <journey-id>
FAIL: <journey-id> — code=<error-code>
ERROR: <journey-id> — <reason>

Latency: total Ts, all under budget
```

Don't paste full JSON. Highlight regressions vs previous runs (`preflight verdict <prev-runId>`) when possible.

## Permissions

`preflight` needs macOS Privacy grants: Accessibility, Screen Recording, Microphone, Input Monitoring. If a run fails with a `tcc-*` error code, run `preflight doctor --install-missing` — it opens the right Privacy panes for the user to toggle. After granting, fully **quit and relaunch** the terminal (TCC grants attach at process launch).
