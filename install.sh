#!/usr/bin/env bash
# Customer-facing preflight installer.
#
# Canonical source lives in the (private) preflight repo at
# `release-templates/preflight-skill/install.sh`. The release workflow
# mirrors it to the public `YouLearn-AI/preflight-skill` repo as
# `install.sh` so customers can bootstrap with:
#
#   curl -fsSL https://raw.githubusercontent.com/YouLearn-AI/preflight-skill/main/install.sh | bash
#
# Designed for "any external user": single Mac, no source access, no
# YouLearn-AI internal context. Verbose-on-failure, idempotent, won't die on
# benign brew warnings (the `rollup` dylib relink message that previously
# tripped `set -e` even though the formula completed cleanly).

set -uo pipefail   # NOTE: deliberately NOT `set -e`. brew + cask installers
                   # sometimes print warnings to stderr that aren't fatal;
                   # we check exit codes explicitly per step.

c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_reset=$'\033[0m'
say()  { printf '%s%s%s\n' "$c_blue"   "→ $1" "$c_reset"; }
ok()   { printf '%s%s%s\n' "$c_green"  "✓ $1" "$c_reset"; }
warn() { printf '%s%s%s\n' "$c_yellow" "! $1" "$c_reset"; }
die()  { printf '%s%s%s\n' "$c_red"    "✗ $1" "$c_reset" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || die "preflight currently supports macOS only."

# `curl | bash` pipes this script over stdin, so plain `read` from stdin
# doesn't reach the user. /dev/tty is the controlling terminal — works for
# both interactive shells and curl-piped invocations as long as the user
# has a real terminal. sudo also reads its password prompt from /dev/tty,
# so the same check tells us whether sudo-requiring steps can succeed.
HAVE_TTY=0
if { : >/dev/tty; } 2>/dev/null; then HAVE_TTY=1; fi

require_tty() {
  # $1: short label of the step that needs a TTY
  if [[ "$HAVE_TTY" != 1 ]]; then
    die "$1 needs an interactive terminal (sudo / keyboard input). Re-run directly in a terminal:
    bash <(curl -fsSL https://raw.githubusercontent.com/YouLearn-AI/preflight-skill/main/install.sh)"
  fi
}

read_tty() {
  # $1: prompt, $2: var name to set
  local prompt="$1" var="$2"
  if [[ "$HAVE_TTY" == 1 ]]; then
    printf '%s' "$prompt" >/dev/tty
    IFS= read -r "$var" </dev/tty || true
  else
    printf '%s' "$prompt"
    IFS= read -r "$var" || true
  fi
}

cat <<EOF

${c_yellow}preflight installer${c_reset}

What you'll see:
  • Homebrew first-install asks for your admin password (one-time).
  • blackhole-2ch (CoreAudio driver) asks for admin password.
  • macOS Privacy panes (Accessibility / Screen Recording / Mic / Input
    Monitoring) require manual toggle later — no installer can grant
    them for you.

After installs, you may need to:
  • Log out + back in (BlackHole 2ch CoreAudio device registration).
  • ${c_yellow}Fully Cmd+Q your terminal and reopen${c_reset} (TCC permissions attach
    only at process launch; running shells don't see new grants).

EOF

# ── Homebrew ──────────────────────────────────────────────────────────────
if ! command -v brew >/dev/null 2>&1; then
  require_tty "Homebrew first-install (sudo password prompt)"
  say "Installing Homebrew (will ask for admin password)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || die "Homebrew install failed. See https://brew.sh"
  if [[ -d /opt/homebrew/bin ]]; then export PATH="/opt/homebrew/bin:$PATH"; fi
  if [[ -d /usr/local/bin ]];   then export PATH="/usr/local/bin:$PATH";   fi
fi
ok "Homebrew $(brew --version | head -1)"

# ── gh CLI (private tap clone needs gh-as-git-credential) ─────────────────
if ! command -v gh >/dev/null 2>&1; then
  say "Installing gh CLI"
  brew install gh || die "brew install gh failed"
fi
if ! gh auth status >/dev/null 2>&1; then
  if [[ "$HAVE_TTY" != 1 ]]; then
    die "gh CLI not authenticated. Run this in your terminal first, then re-run the installer:
    gh auth login"
  fi
  say "Run: gh auth login (opens browser)"
  gh auth login </dev/tty || die "gh auth failed — re-run after authenticating"
fi
gh auth setup-git
ok "gh authenticated as $(gh api user --jq .login)"

# ── Public Homebrew deps ──────────────────────────────────────────────────
# Some packages are commonly installed via npm (`npm install -g pnpm`) before
# brew gets to them; the resulting symlink at $(brew --prefix)/bin/$pkg
# isn't owned by Homebrew, so a plain `brew install` errors with "already
# exists" and bails. `brew link --overwrite` reclaims the symlink.
brew_install() {
  local pkg="$1" cask_flag="${2:-}"
  if [[ "$cask_flag" == "cask" ]]; then
    if brew list --cask --versions "$pkg" >/dev/null 2>&1; then
      ok "$pkg (cask) already installed"
      return 0
    fi
    say "Installing $pkg cask"
    brew install --cask "$pkg" || die "brew install --cask $pkg failed"
  else
    if brew list --versions "$pkg" >/dev/null 2>&1; then
      ok "$pkg already installed"
      return 0
    fi
    say "Installing $pkg"
    if ! brew install "$pkg" 2>&1 | tee "/tmp/preflight-brew-${pkg}.log"; then
      # Most common cause: a non-brew binary already at $prefix/bin/$pkg
      # (e.g. an `npm install -g pnpm` symlink). `--overwrite` reclaims it.
      if grep -qE "already exists|Could not symlink|target /.+/bin/$pkg" "/tmp/preflight-brew-${pkg}.log" 2>/dev/null; then
        warn "$pkg link conflict detected — running 'brew link --overwrite $pkg'"
        brew link --overwrite "$pkg" || die "brew link --overwrite $pkg failed"
      else
        # Some formulae (preflight, electron deps) print non-fatal dylib
        # relink warnings AFTER the formula is fully installed and on PATH.
        # Verify the binary is actually present before deciding we failed.
        if brew list --versions "$pkg" >/dev/null 2>&1; then
          warn "brew install $pkg printed warnings but the formula is installed; continuing"
        else
          die "brew install $pkg failed (log: /tmp/preflight-brew-${pkg}.log)"
        fi
      fi
    fi
  fi
}

brew_install node
brew_install pnpm
brew_install ffmpeg
brew_install tesseract
require_tty "blackhole-2ch (CoreAudio driver, sudo)"
brew_install blackhole-2ch cask

# ── audiokit (no Homebrew tap) ────────────────────────────────────────────
if command -v audiokit >/dev/null 2>&1; then
  ok "audiokit already on PATH ($(command -v audiokit))"
else
  AUDIOKIT_DIR="${AUDIOKIT_DIR:-$HOME/.local/share/preflight/audiokit}"
  if [[ ! -d "$AUDIOKIT_DIR/.git" ]]; then
    say "Cloning audiokit → $AUDIOKIT_DIR"
    mkdir -p "$(dirname "$AUDIOKIT_DIR")"
    git clone --depth 1 https://github.com/YouLearn-AI/audiokit.git "$AUDIOKIT_DIR" \
      || die "git clone audiokit failed"
  else
    say "audiokit checkout exists, fast-forwarding"
    git -C "$AUDIOKIT_DIR" pull --ff-only || warn "couldn't fast-forward audiokit — leaving as is"
  fi
  ( cd "$AUDIOKIT_DIR" && npm install --silent && npm link ) \
    || die "audiokit npm install/link failed"
  if command -v audiokit >/dev/null 2>&1; then
    ok "audiokit on PATH"
  else
    warn "audiokit not on PATH after npm link — check that \$(npm config get prefix)/bin is in PATH"
  fi
fi

# ── cua-driver (no Homebrew tap) ──────────────────────────────────────────
if command -v cua-driver >/dev/null 2>&1; then
  ok "cua-driver already on PATH ($(command -v cua-driver))"
else
  require_tty "cua-driver upstream installer (sudo for /Applications)"
  say "Installing cua-driver from upstream (trycua/cua)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.sh)" \
    || warn "upstream cua-driver installer reported non-zero — checking PATH"
  if ! command -v cua-driver >/dev/null 2>&1; then
    # The upstream installer drops /Applications/CuaDriver.app; symlink
    # ourselves onto PATH if the bundle landed.
    TARGET="/Applications/CuaDriver.app/Contents/MacOS/cua-driver"
    if [[ -x "$TARGET" ]]; then
      if [[ -d /opt/homebrew/bin ]]; then
        ln -sf "$TARGET" /opt/homebrew/bin/cua-driver
      else
        mkdir -p "$HOME/.local/bin"
        ln -sf "$TARGET" "$HOME/.local/bin/cua-driver"
        warn "cua-driver symlinked to ~/.local/bin — make sure that's on your PATH"
      fi
    else
      die "cua-driver install failed — /Applications/CuaDriver.app not present"
    fi
  fi
  ok "cua-driver $(cua-driver --version 2>&1 | head -1 || echo 'present')"
fi

# ── preflight binary (private brew tap) ───────────────────────────────────
# Why this section is robust: brew sometimes prints a non-fatal
# "rollup dylib relink" warning to stderr during `brew install preflight`,
# which makes the install LOOK failed (exit 1) even though the formula
# completed and `preflight` is on PATH. We disable -e here, then verify
# success by checking the binary directly.
say "Tapping YouLearn-AI/homebrew-preflight (private)"
brew tap YouLearn-AI/homebrew-preflight git@github.com:YouLearn-AI/homebrew-preflight.git \
  >/dev/null 2>&1 || true

if ! command -v preflight >/dev/null 2>&1; then
  say "brew install preflight"
  brew install preflight 2>&1 | tee /tmp/preflight-brew-install.log || true

  if ! command -v preflight >/dev/null 2>&1; then
    cat <<EOF >&2

${c_red}preflight is still not on PATH after brew install.${c_reset}

Most likely your GitHub user ($(gh api user --jq .login 2>/dev/null || echo '?'))
isn't a collaborator on YouLearn-AI/homebrew-preflight yet, so the formula
couldn't be fetched. Ping your YouLearn-AI contact with your GitHub username
and they'll grant access.

Brew install log: /tmp/preflight-brew-install.log
EOF
    exit 1
  fi
fi
ok "preflight $(preflight --version 2>&1 | head -1)"

# ── Skill ─────────────────────────────────────────────────────────────────
# Try three sources in order, falling back through each:
#   1. The freshly-installed brew prefix (matches the binary version exactly).
#   2. A local sibling SKILL.md if this script was bash <(...) from a clone.
#   3. The public preflight-skill repo's main branch (may lag a release).
SKILL_DIR="$HOME/.claude/skills/preflight"
mkdir -p "$SKILL_DIR"
SKILL_INSTALLED=0
BREW_SKILL="$(brew --prefix preflight 2>/dev/null)/share/preflight/SKILL.md"
LOCAL_SKILL="$(dirname "${BASH_SOURCE[0]:-$0}")/skills/preflight/SKILL.md"
if [[ -f "$BREW_SKILL" ]]; then
  cp "$BREW_SKILL" "$SKILL_DIR/SKILL.md" \
    && { ok "Claude Code skill at $SKILL_DIR/SKILL.md (from brew prefix)"; SKILL_INSTALLED=1; }
elif [[ -f "$LOCAL_SKILL" ]]; then
  cp "$LOCAL_SKILL" "$SKILL_DIR/SKILL.md" \
    && { ok "Claude Code skill at $SKILL_DIR/SKILL.md (from local clone)"; SKILL_INSTALLED=1; }
fi
if [[ "$SKILL_INSTALLED" != 1 ]]; then
  if curl -fsSL https://raw.githubusercontent.com/YouLearn-AI/preflight-skill/main/skills/preflight/SKILL.md \
     -o "$SKILL_DIR/SKILL.md" 2>/dev/null && [[ -s "$SKILL_DIR/SKILL.md" ]]; then
    ok "Claude Code skill at $SKILL_DIR/SKILL.md (from public mirror)"
  else
    warn "couldn't install SKILL.md from any source — Claude Code will still work; copy it from /opt/homebrew/share/preflight/SKILL.md later"
  fi
fi

# ── API keys ──────────────────────────────────────────────────────────────
case "${SHELL:-}" in
  */zsh)  rc="$HOME/.zshrc" ;;
  */bash) rc="$HOME/.bashrc" ;;
  *)      rc="$HOME/.profile" ;;
esac

prompt_api_key() {
  # $1 var, $2 label, $3 url, $4 required(true|false)
  local var="$1" label="$2" url="$3" required="$4"
  # Indirect expansion via printf -v stays well-defined under `set -u`
  # (where ${!var:-} can trip on bash 3.2 macOS default).
  local current=""
  printf -v current '%s' "${!var-}" 2>/dev/null || current=""
  if [[ -n "$current" ]]; then
    ok "$label already set (${#current} chars)"
    return 0
  fi
  echo
  if [[ "$required" == "true" ]]; then
    say "$label: not set (REQUIRED)"
  else
    say "$label: not set (recommended)"
  fi
  echo "    Get a key: ${c_yellow}$url${c_reset}"
  if [[ "$HAVE_TTY" != 1 ]]; then
    warn "Skipped — no TTY for paste. Set later: export $var=... in $rc"
    return 0
  fi
  local val=""
  read_tty "    Paste your $var now (or press Enter to skip): " val
  if [[ -z "${val:-}" ]]; then
    echo "    Skipped. Set later with: export $var=..."
    return 0
  fi
  if ! grep -q "^export $var=" "$rc" 2>/dev/null; then
    printf '\n# preflight\nexport %s=%q\n' "$var" "$val" >> "$rc"
    ok "Added $var to $rc — fully quit + relaunch your terminal to pick it up"
  else
    echo "    $var already in $rc — leaving as is"
  fi
  export "$var=$val"
}

prompt_api_key OPENAI_API_KEY "OPENAI_API_KEY (workflow brain)" \
  "https://platform.openai.com/api-keys" true
prompt_api_key GEMINI_API_KEY "GEMINI_API_KEY (vision self-heal)" \
  "https://aistudio.google.com/apikey" false

# ── cua agent-cursor overlay ──────────────────────────────────────────────
if command -v cua-driver >/dev/null 2>&1; then
  cua-driver call set_config '{"key": "agent_cursor.enabled", "value": true}' \
    >/dev/null 2>&1 \
    && ok "cua agent_cursor.enabled = true (persisted)" \
    || warn "couldn't persist cua agent_cursor — non-fatal"
fi

# ── Version sanity ────────────────────────────────────────────────────────
# The brew tap can lag the source repo if a release CI run is mid-flight or
# the auto-bump PR is unmerged. Surface the installed version prominently
# AND warn if it's older than what the public skill repo expects.
INSTALLED_VERSION="$(preflight --version 2>&1 | head -1 | tr -d 'v ')"
EXPECTED_VERSION="$(curl -fsSL https://raw.githubusercontent.com/YouLearn-AI/preflight-skill/main/.version 2>/dev/null || true)"
if [[ -n "$EXPECTED_VERSION" && -n "$INSTALLED_VERSION" && "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ]]; then
  warn "preflight $INSTALLED_VERSION installed but the public skill repo expects $EXPECTED_VERSION."
  warn "The brew tap formula likely hasn't been bumped yet. Try 'brew update && brew upgrade preflight' in a few minutes."
fi

# ── Doctor ────────────────────────────────────────────────────────────────
echo
say "Running preflight doctor"
preflight doctor --install-missing || true   # warns are fine; doctor's overall
                                             # is informational not gating

cat <<EOF

${c_green}Done — preflight ${INSTALLED_VERSION:-installed}.${c_reset}

Next steps (in this order):

  1. Open System Settings → Privacy & Security → grant your terminal:
     Accessibility · Input Monitoring · Screen Recording · Microphone
     (Doctor opens these panes if any are denied.)

  2. ${c_yellow}Fully Cmd+Q this terminal and reopen${c_reset} — TCC grants attach at
     process launch.

  3. Then verify:
       preflight doctor          # expect overall: ok (Karabiner warn is fine)
       preflight smoke           # expect verdict: pass (~30s)

  4. First real run — paste the prompt your YouLearn-AI contact sent you
     into Claude Code / Cursor / Codex. The agent picks up the skill at
     ~/.claude/skills/preflight/SKILL.md and drives the rest hands-off.

EOF
