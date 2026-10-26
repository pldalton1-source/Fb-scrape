#!/usr/bin/env bash
# One-shot installer for the Fb-scrape marketplace monitor.
#
# Idempotent — safe to re-run. It never overwrites an existing
# config/credentials.toml, so re-running cannot destroy your secrets.
#
# Usage:  ./setup.sh [--skip-browser]
set -euo pipefail
cd "$(dirname "$0")"

AIMM_VERSION='0.10.2'
VENV='.venv'
SKIP_BROWSER=0

for arg in "$@"; do
    case "$arg" in
        --skip-browser) SKIP_BROWSER=1 ;;
        -h|--help)
            awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
            exit 0 ;;
        *)
            echo "Unknown option: $arg (try --help)" >&2
            exit 2 ;;
    esac
done

step() { printf '\n==> %s\n' "$1"; }
note() { printf '    %s\n' "$1"; }
die()  { printf '\nFAILED: %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- 1. python
step "Checking Python"
command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH."
python3 - <<'PY' || die "Python 3.10+ is required (ai-marketplace-monitor $AIMM_VERSION requires >=3.10)."
import sys
sys.exit(0 if sys.version_info >= (3, 10) else 1)
PY
note "$(python3 --version)"

# ------------------------------------------------------------------ 2. venv
step "Creating virtualenv in $VENV"
if [[ -d "$VENV" ]]; then
    note "already exists — reusing it"
else
    python3 -m venv "$VENV" || die "could not create the virtualenv."
    note "created"
fi

step "Installing ai-marketplace-monitor==$AIMM_VERSION"
"$VENV/bin/pip" install --quiet --disable-pip-version-check \
    "ai-marketplace-monitor==$AIMM_VERSION" \
    || die "pip install failed. If this is a network error, pypi.org and files.pythonhosted.org must be reachable."
note "$("$VENV/bin/pip" show ai-marketplace-monitor | sed -n 's/^Version: /installed version /p')"

# --------------------------------------------------------------- 3. browser
if (( SKIP_BROWSER )); then
    step "Skipping browser install (--skip-browser)"
else
    step "Downloading the Chromium build Playwright expects"
    "$VENV/bin/playwright" install chromium \
        || die "browser download failed. This needs cdn.playwright.dev to be reachable."
    note "chromium installed"

    if [[ "$(uname -s)" == "Linux" ]]; then
        step "Installing Chromium's system libraries (Linux only, needs sudo)"
        if command -v sudo >/dev/null 2>&1; then
            if sudo "$VENV/bin/playwright" install-deps chromium; then
                note "system libraries installed"
            else
                note "install-deps failed — the smoke test below will tell you if it matters"
            fi
        else
            note "sudo not available; skipping. If the smoke test below fails, run:"
            note "  sudo $VENV/bin/playwright install-deps chromium"
        fi
    fi
fi

# ----------------------------------------------------------- 4. credentials
step "Setting up config/credentials.toml"
if [[ -f config/credentials.toml ]]; then
    note "already exists — left untouched"
else
    cp config/credentials.example.toml config/credentials.toml
    chmod 600 config/credentials.toml
    note "created from the template, mode 600"
fi

# ------------------------------------------------------------- 5. self-test
step "Self-test: does the installed tool accept this config?"
"$VENV/bin/python" - <<'PY' || die "the config did not load. Fix the error above before running the monitor."
import logging, sys
from pathlib import Path

logging.basicConfig(level=logging.CRITICAL, format="%(message)s")
from ai_marketplace_monitor.config import Config

try:
    c = Config(
        [Path("config/bikes.toml"), Path("config/credentials.toml")],
        logging.getLogger("setup"),
    )
except Exception as e:
    print(f"    config FAILED: {type(e).__name__}: {e}")
    sys.exit(1)

print(f"    config OK — {len(c.item)} items, "
      f"marketplace: {', '.join(sorted(c.marketplace))}, "
      f"AI backend: {', '.join(sorted(c.ai)) or 'none'}")
PY

step "Self-test: can a headless browser actually launch?"
"$VENV/bin/python" - <<'PY' || die "the browser could not launch — see the error above.
  'Executable doesn't exist'  -> the build is not downloaded:  $VENV/bin/playwright install chromium
  anything else, on Linux     -> missing system libraries:     sudo $VENV/bin/playwright install-deps chromium"
import sys
try:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True)
        v = b.version
        b.close()
except Exception as e:
    print(f"    browser FAILED: {type(e).__name__}: {e}")
    sys.exit(1)
print(f"    browser OK — Chromium {v}")
PY

# ---------------------------------------------------------------- 6. gotcha
if [[ -s "$HOME/.ai-marketplace-monitor/config.toml" ]]; then
    step "WARNING: a stray global config is in play"
    note "$HOME/.ai-marketplace-monitor/config.toml exists and is ALWAYS merged in"
    note "on top of this repo's files. Empty or remove it so this repo stays the"
    note "single source of truth."
fi

# ----------------------------------------------------------------- 7. what's left
step "Done. What's left"
if grep -v '^[[:space:]]*#' config/credentials.toml | grep -q REPLACE_ME; then
    note "1. Fill in the REPLACE_ME values in config/credentials.toml:"
    grep -n REPLACE_ME config/credentials.toml \
        | grep -v '^[0-9]*:[[:space:]]*#' | sed 's/^/       /'
    note ""
    note "2. Then run ONCE with a visible browser to clear the Facebook login:"
    note "   $VENV/bin/ai-marketplace-monitor \\"
    note "       --config config/bikes.toml --config config/credentials.toml"
    note ""
    note "3. After the login is cached, start it headless:"
    note "   ./run-monitor.sh"
else
    note "credentials.toml has no placeholders left."
    note ""
    note "If you have not yet completed the Facebook login on this machine, run"
    note "ONCE with a visible browser so the session gets cached:"
    note "   $VENV/bin/ai-marketplace-monitor \\"
    note "       --config config/bikes.toml --config config/credentials.toml"
    note ""
    note "Otherwise you are ready:"
    note "   ./run-monitor.sh"
fi
