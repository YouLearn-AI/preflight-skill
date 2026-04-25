#!/usr/bin/env bash
# preflight installer (external customer path)
#
#   curl -fsSL https://raw.githubusercontent.com/YouLearn-AI/preflight-skill/main/install.sh | bash
#
# Installs:
#   1. Homebrew (if missing)
#   2. Public deps: node, pnpm, ffmpeg, tesseract, blackhole-2ch (cask)
#   3. audiokit (git clone + npm link from public YouLearn-AI/audiokit)
#   4. cua-driver (upstream curl-bash installer from trycua/cua)
#   5. preflight binary from YouLearn-AI/homebrew-preflight (private tap)
#   6. Claude Code skill at ~/.claude/skills/preflight/
#   7. Walks through macOS Privacy permissions
#
# Authentication: requires `gh auth login` to access the private brew tap.

set -euo pipefail

c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_reset=$'\033[0m'
say()  { printf '%s%s%s\n' "$c_blue"   "→ $1" "$c_reset"; }
ok()   { printf '%s%s%s\n' "$c_green"  "✓ $1" "$c_reset"; }
warn() { printf '%s%s%s\n' "$c_yellow" "! $1" "$c_reset"; }
die()  { printf '%s%s%s\n' "$c_red"    "✗ $1" "$c_reset" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || die "preflight currently supports macOS only."

cat <<EOF

${c_yellow}Heads up:${c_reset}
  • Homebrew first-install asks for your admin password (one-time).
  • blackhole-2ch (CoreAudio driver) asks for admin password.
  • Privacy panes (Accessibility / Screen Recording / Mic / Input Monitoring)
    require manual toggle — preflight cannot grant them.

After installs, you may need to:
  • Log out and back in (BlackHole 2ch CoreAudio device registration).
  • Quit and relaunch your terminal (TCC permission grants attach at launch).

EOF

# Homebrew
if ! command -v brew >/dev/null 2>&1; then
  say "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -d /opt/homebrew/bin ]]; then export PATH="/opt/homebrew/bin:$PATH"; fi
fi
ok "Homebrew $(brew --version | head -1)"

# gh CLI auth check (needed for private tap)
if ! command -v gh >/dev/null 2>&1; then
  say "Installing gh"
  brew install gh
fi
if ! gh auth status >/dev/null 2>&1; then
  say "Run: gh auth login"
  gh auth login
fi
ok "gh authenticated as $(gh api user --jq .login)"

# Public deps via Homebrew
for pkg in node pnpm ffmpeg tesseract; do
  brew list --versions "$pkg" >/dev/null 2>&1 || (say "Installing $pkg" && brew install "$pkg")
done
brew list --cask --versions blackhole-2ch >/dev/null 2>&1 || (say "Installing blackhole-2ch" && brew install --cask blackhole-2ch)

# audiokit — git clone + npm link (no Homebrew tap)
if ! command -v audiokit >/dev/null 2>&1; then
  say "Installing audiokit (clone + npm link)"
  AUDIOKIT_DIR="${AUDIOKIT_DIR:-$HOME/Projects/audiokit}"
  if [[ ! -d "$AUDIOKIT_DIR/.git" ]]; then
    mkdir -p "$(dirname "$AUDIOKIT_DIR")"
    git clone https://github.com/YouLearn-AI/audiokit.git "$AUDIOKIT_DIR"
  fi
  ( cd "$AUDIOKIT_DIR" && npm install --silent && npm link --silent )
fi
ok "audiokit $(audiokit --version 2>/dev/null || echo present)"

# cua-driver — upstream curl-bash installer (no Homebrew tap)
if ! command -v cua-driver >/dev/null 2>&1; then
  say "Installing cua-driver"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.sh)"
fi
ok "cua-driver $(cua-driver --version 2>/dev/null || echo present)"

# Private preflight tap (gated to customer's GitHub user)
say "Tapping private preflight brew tap"
brew tap YouLearn-AI/homebrew-preflight git@github.com:YouLearn-AI/homebrew-preflight.git 2>&1 | grep -v "already tapped" || true

say "Installing preflight"
brew install preflight || die "brew install preflight failed — ask your YouLearn-AI contact to add your GitHub user (\$(gh api user --jq .login)) as a collaborator on YouLearn-AI/homebrew-preflight"

# Skill
say "Installing Claude Code skill"
SKILL_DIR="$HOME/.claude/skills/preflight"
mkdir -p "$SKILL_DIR"
curl -fsSL https://raw.githubusercontent.com/YouLearn-AI/preflight-skill/main/skills/preflight/SKILL.md > "$SKILL_DIR/SKILL.md"
ok "Skill installed at $SKILL_DIR"

# Doctor + permissions
say "Running preflight doctor"
echo
preflight doctor --install-missing || true

echo
ok "Done."
echo
echo "Try it:"
echo "  preflight list"
echo "  preflight smoke"
echo
echo "Or in Cursor / Claude Code, ask: 'run preflight smoke' or 'is this safe to ship?'"
