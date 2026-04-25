---
name: preflight
description: Run pre-release QA flows for the customer's app. Use when the user asks to "run preflight", "QA before push", "smoke test", "is this safe to ship", "check the dictation flows", or similar pre-release verification asks. Background-only — never disturbs the user's foreground app.
---

# preflight skill

End-to-end regression testing for shipped Electron desktop apps on macOS. Drives the binary through a real audio + accessibility pipeline, captures verdicts, surfaces regressions.

## When the user asks for QA

| User says | You run |
|---|---|
| "run preflight" / "smoke test" / "is this safe to push" | `preflight smoke` |
| "what flows can be tested" | `preflight list` |
| "is the env set up" | `preflight doctor` |
| "fix missing deps" | `preflight doctor --install-missing` |
| "run a custom flow" | `preflight run <journey-id>` (find ids via `preflight list`) |
| "compare to last run" | `preflight verdict <prev-run-id>` |

## Reading results

Each `preflight run` emits JSON to stdout. Surface to the user:
- `verdict` — `pass | fail | error`
- `errors[]` — array of `{code, message}`. Empty = clean.
- `latency.budget.met` — boolean.

Don't trust verdict alone — always inspect `errors[]` and budget.

## Architecture (so you understand what you're driving)

- **Audio**: `audiokit inject device <wav> --set-input` plays through BlackHole 2ch (virtual mic). The customer's app reads it as real input.
- **Trigger / IPC**: Electron CDP via `localhost:9222` (the customer's app must be launched with `--remote-debugging-port=9222`).
- **App interactions**: cua-driver daemon. AX-mode `click`, `set_value`, `get_window_state`. All BG, no foreground change.
- **Verification**: app DB + log + AX state.

## Anti-patterns

- Don't modify the customer's app bundle (signature breaks).
- Don't `osascript keystroke` to drive target apps (needs frontmost). Use cua's BG primitives (`press_key`, `hotkey`, `type_text_chars` — postToPid).
- Don't relaunch the target app in foreground (`open -a` activates). Use `open -ga --args ...`.

## Reporting

Use this format when reporting to the user:

```
preflight smoke — N journeys, M failed in Ts

PASS: <journey-id>
FAIL: <journey-id> — code=<error-code>
ERROR: <journey-id> — <reason>

Latency: total Ts, all under budget
```

Don't paste full JSON. Highlight regressions vs previous runs when possible.

## Permissions

`preflight` needs macOS Privacy grants: Accessibility, Screen Recording, Microphone, Input Monitoring. If a run fails with a `tcc-*` error code, run `preflight doctor --install-missing` — it opens the right Privacy panes for the user to toggle. After granting, the user must fully **quit and relaunch** their terminal (TCC grants attach at process launch).
