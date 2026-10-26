#!/usr/bin/env bash
# Start the marketplace monitor with the version-controlled search
# config plus the local (gitignored) credentials file.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f config/credentials.toml ]]; then
    echo "config/credentials.toml not found." >&2
    echo "Run: cp config/credentials.example.toml config/credentials.toml" >&2
    echo "then fill in the REPLACE_ME values." >&2
    exit 1
fi

# Only real settings count: the template's own comments mention REPLACE_ME,
# so an unfiltered grep refuses to start even when every value is filled in.
if grep -v '^[[:space:]]*#' config/credentials.toml | grep -q REPLACE_ME; then
    echo "config/credentials.toml still contains REPLACE_ME placeholders — fill them in first." >&2
    grep -n REPLACE_ME config/credentials.toml | grep -v '^[0-9]*:[[:space:]]*#' >&2
    exit 1
fi

# On a desktop, drop --headless for the first run so you can complete
# the Facebook login / CAPTCHA in the visible browser window; the
# session is cached afterwards.
exec .venv/bin/ai-marketplace-monitor \
    --config config/bikes.toml \
    --config config/credentials.toml \
    --headless \
    "$@"
