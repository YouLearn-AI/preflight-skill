---
name: preflight
description: Run pre-release QA flows for VoiceOS — dictation, agent mode, settings, onboarding, customer walkthroughs. Use when the user says "run preflight", "QA before push", "smoke test", "is this safe to ship", "test the dictation flow", "run jonah", "test onboarding", "find regressions", or any pre-release verification ask. Background-only by default — never disturbs the user's foreground app unless paste verification requires it.
---

# preflight skill

End-to-end regression testing for VoiceOS (and other Electron desktop apps). Workflows live as **`.md` files** under `journeys/<customer>/walkthroughs/` — natural language, source of truth (Rule 17). The CLI's brain (GPT-5.5) decomposes each workflow into tool calls; the harness primitives execute via cua-driver (MCP, BG-default), audiokit, CDP, sqlite. Vision-based self-heal via Gemini 3.1 Pro fires only on UI-rename misses (Rule 16, ~$0.0002/heal).

The full doctrine is in **[`AGENTS.md`](../../../AGENTS.md)** (17 rules). This skill is the user-facing routing + orchestration layer.

## When the user asks X, you do Y

| User says | Run |
|---|---|
| "run preflight" / "QA before push" / "is this safe to ship" | `preflight smoke` |
| "test jonah" / "run jonah's walkthrough" | `preflight workflow jonah-customer-video` |
| "test onboarding" / "fresh-install onboarding" | `preflight workflow onboarding-fresh-mac` |
| "list workflows" / "what can I test" | `preflight workflows` |
| "list registered TS journeys" | `preflight list` |
| "smoke test" (fast subset) | `preflight smoke` |
| "is the env set up" | `preflight doctor` |
| "fix missing deps" | `preflight doctor --install-missing` |
| "run jonah 2 times" / "false-positive filter" | `preflight workflow jonah-customer-video --reps 2` (Rule 15 — restart between reps) |
| "show me the plan first" | `preflight workflow jonah-customer-video --dry-run` |

## Onboarding (first-time customer setup)

Walk a new customer through this in order:

1. **Install:** customers run `curl -fsSL https://raw.githubusercontent.com/YouLearn-AI/preflight-skill-mvp-prototype/main/install.sh | bash` (taps the private `YouLearn-AI/homebrew-preflight-mvp-prototype` brew tap for the prebuilt binary; installs audiokit via `git clone + npm link` and cua-driver via the upstream curl-bash). Internal teammates with source: `./install.sh` from the cloned repo.
2. **`preflight doctor --install-missing`** — brews missing public deps (blackhole-2ch, ffmpeg, tesseract); installs audiokit + cua-driver from their upstream public repos (no Homebrew tap exists for either); opens **System Settings → Privacy & Security** panes for permission grants: **Accessibility, Input Monitoring, Screen Recording, Microphone**.
3. **Quit + relaunch terminal** after granting (TCC grants attach at process launch).
4. **API keys** — `install.sh` prompts for both. If skipped:
   - `OPENAI_API_KEY` (required) — GPT-5.5 brain. Get at https://platform.openai.com/api-keys.
   - `GEMINI_API_KEY` (recommended) — Rule 16 vision heal. Free at https://aistudio.google.com/apikey.
5. **`preflight workflows`** — confirm walkthrough discovery.
6. **`preflight workflow jonah-customer-video --dry-run`** — emits the plan without executing. Confidence-builder.
7. **`preflight workflow jonah-customer-video`** — first real run.

## Tools the CLI gives the brain

The brain (`scripts/run_workflow.py`) has these tools — you don't call them directly, the brain does:

| Tool | Mode | Purpose |
|---|---|---|
| `cdp_eval` | BG | JS in renderer (window.api.*, DOM .click(), store reads) |
| `audiokit_inject` | BG | WAV through BlackHole 2ch virtual mic |
| `sqlite_query` | BG | VoiceOS DB read (`voice_sessions`, `voice_session_history`) |
| `log_tail` | BG | main.log filter |
| `cua_get_window_state` | BG | AX tree (Markdown with `[N] AXButton` tags) + screenshot |
| `cua_click` (element_index) | BG | AX press, fires Electron React, animates agent cursor |
| `cua_type_text` | BG | AXSetAttribute typing into focused element |
| `cua_hotkey` | FG-aware | Global event-tap key combo |
| `apps_capture_frontmost` | BG | Bundle id of frontmost (for restore in cleanup) |
| `apps_activate` | FG | Bring app to FG — only when Rule 5a justifies (paste verification, FG dictation) |
| `restart_voiceos` | BG | Rule 15 reset — kill+relaunch with CDP+AX flags, poll until pill ready |
| `heal_locate` | BG | Gemini 3.1 Pro vision → coords + click. Last-resort when AX-tree-grep can't find a button |

Default is BG everything. The brain calls `apps_activate` only when the workflow .md says so.

## Authoring a new workflow `.md` (when user describes what to test)

When the user says "test X" or "add a workflow for Y" or describes a customer video, **author a new `.md` under `journeys/<customer>/walkthroughs/<id>.md`**. The customer doesn't write code — they describe the journey in English; you turn it into a workflow file.

**Schema reference:** [`journeys/voiceos/walkthroughs/SCHEMA.md`](../../../journeys/voiceos/walkthroughs/SCHEMA.md) is the spec. Front-matter (YAML) + body sections (Markdown).

**Template:**

```markdown
---
id: <kebab-case-id>
customer: <voiceos|aquavoice|...>
description: One line.
fixtures:
  - fixtures/<customer>/audio/some-fixture.wav
expected_duration_s: 600
tags: [agent, dictation, ...]
preflight:
  - <precondition 1>
  - <precondition 2>
---

# <Workflow Title>

## Goal
1-3 sentences on what this verifies.

## Pre-flight
- Capture initial frontmost (Rule 2).
- Verify VoiceOS state (e.g., onboarding completed via eval_in_app).

## Steps

### Step 1: <imperative title>
What the user does (paragraph or bullets).

**Verify:**
- Concrete assertion 1 (DB row, AX state, IPC return)
- Concrete assertion 2

**Self-heal hints:** (optional)
- If <symptom>, then <action>.

### Step 2: ...

## Cleanup
- Restore frontmost.
- Remove test artifacts (Spelling entries, Replacements, etc.).
```

**Authoring rules:**

1. **Plain English in steps.** Don't write tool calls. The brain decomposes "click Customize" into `inspect_window` + `click_element`. Tool hints are optional and only when the obvious tool isn't obvious.
2. **Concrete verifications.** Each step's "Verify" must be checkable (DB row, log substring, AX-tree match, target-app body content). "It works" is not a verification.
3. **Self-target writes (Rule 7).** Never email/DM a third party from a workflow. Use `achyut.benz@gmail.com` (or whoever the user is) for self-targeted writes.
4. **Self-heal hints capture domain knowledge** the brain can't infer (known false positives, app-specific composer recipes, log-line gotchas).
5. **Discoverable id.** `id` in front-matter must match filename and be unique within the customer's `walkthroughs/` directory. `preflight workflows` lists discovered files.

**Verify the file before running:** `preflight workflow <id> --dry-run` emits the brain's plan without executing — confidence-builder, costs ~1 LLM call.

## Editing an existing workflow on UI drift

When the brain emits `propose_md_edit` events (the workflow's wording no longer matches the UI), use the **Edit** tool to apply the proposed change. The CLI doesn't auto-edit `.md` files for safety — that's your job, with diff confirmation. Don't edit `scripts/voiceos_ui_drivers.py` to "make a test pass" — edit the `.md` (Rule 17).

## Multi-step orchestration (your job, not the CLI's)

The CLI runs ONE workflow and emits ONE verdict JSON. Multi-run synthesis, FINDINGS authoring, git commits, and PR creation are **your** responsibility:

```
User: "run jonah, file any new bugs"

You:
1. preflight workflow jonah-customer-video --reps 2     # Rule 15
2. Read verdict JSON; classify per step (pass-stable / fail-stable / flaky)
3. For each fail-stable: examine heal_events + tool_call_log; decide if it's
   a workflow-md drift (UI rename → propose .md edit) or a real product bug
4. Append a Wave-N section to journeys/voiceos/FINDINGS.md with repros + log evidence
5. git commit (no Co-Authored-By trailer per user's saved memory)
6. git push if requested
7. Reply with concise summary
```

## Self-heal (your hands, not the CLI's)

When `preflight workflow` emits `propose_md_edit` events:

```json
{"propose_md_edit": {"reason": "Customize button renamed to 'Settings'", "search": "Customize tab in left navigation", "replace": "Settings tab in left navigation"}}
```

- If correct (AX tree confirms the rename): use **Edit** to update the workflow .md, then re-run.
- If wrong (LLM hallucination): don't apply, surface to user.
- Workflow .md is the only thing edited on UI drift. Harness primitives stay stable. (Rule 17.)

## Debugging a failure

When `verdict: "fail"`:

1. Read `step_records[N].evidence` — DB rows, AX state, log lines, screenshots.
2. Read `tool_call_log[]` — last ~50 tool calls. Spot the wrong return.
3. Read `heal_events[]` — what did Gemini suggest?
4. Hypothesize: methodology / inter-test residual / real product bug (Rule 12).
5. Try once with a different approach (`--reps 2 --restart-between-reps`) before reporting.
6. If methodology: edit the workflow .md.
7. If product bug: file in FINDINGS.md with full repro.

## Anti-patterns

Don't:
- `osascript -e 'tell to keystroke'` — use `cua_type_text` / `cua_hotkey` via a workflow.
- Edit `scripts/voiceos_ui_drivers.py` to "fix" a test — edit the workflow .md (Rule 17).
- Bring VoiceOS to FG in BG runs — the brain handles `apps_activate` only when the .md explicitly requires it.
- Skip `preflight doctor` on a fresh machine — TCC grants are silent killers.

## Reporting format

After a run finishes:

> **{verdict}** — {pass}/{total} steps · {duration_s}s · {heal_events.length} heal events
>
> {one-line summary}
>
> [if fails]
> Failures:
> - step-{N}: {title} → {failure_mode_classification}
>
> Run dir: `out/{run_id}/`. Recording: `~/Movies/preflight-recordings/{run_id}.mp4` (if recorded).

Concise. Don't dump full step_records — they're in the JSON on disk.
