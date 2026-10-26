#!/usr/bin/env bash
# Start the marketplace monitor with the version-controlled search
# config plus the local (gitignored) credentials file.
set -euo pipefail
cd "$(dirname "$0")"

# Which credentials file to merge in. Override to use the environment
# variable form:  CREDENTIALS=config/credentials.env.toml ./run-monitor.sh
CREDENTIALS="${CREDENTIALS:-config/credentials.toml}"

if [[ ! -f "$CREDENTIALS" ]]; then
    echo "$CREDENTIALS not found." >&2
    echo "Run: ./setup.sh   (or: cp config/credentials.example.toml config/credentials.toml)" >&2
    echo "then fill in the REPLACE_ME values." >&2
    echo "To keep secrets out of files entirely, set them in the environment and use:" >&2
    echo "  CREDENTIALS=config/credentials.env.toml $0" >&2
    exit 1
fi

# Only real settings count: the template's own comments mention REPLACE_ME,
# so an unfiltered grep refuses to start even when every value is filled in.
if grep -v '^[[:space:]]*#' "$CREDENTIALS" | grep -q REPLACE_ME; then
    echo "$CREDENTIALS still contains REPLACE_ME placeholders — fill them in first." >&2
    grep -n REPLACE_ME "$CREDENTIALS" | grep -v '^[0-9]*:[[:space:]]*#' >&2
    exit 1
fi

# Every ${VAR} the credentials file references must actually be set.
# Not all of these fail loudly on their own: a missing Anthropic key
# raises at startup, but missing Pushover keys do not — the monitor would
# run, match listings and silently never notify. So check them all here.
missing=()
while IFS= read -r var; do
    [[ -n "$var" ]] || continue
    [[ -n "${!var:-}" ]] || missing+=("$var")
done < <(grep -v '^[[:space:]]*#' "$CREDENTIALS" \
         | grep -o '\${[A-Za-z_][A-Za-z0-9_]*}' | tr -d '${}' | sort -u)

if (( ${#missing[@]} )); then
    echo "$CREDENTIALS references environment variables that are not set:" >&2
    printf '    %s\n' "${missing[@]}" >&2
    echo "Set them in your environment's settings, then start a new session." >&2
    exit 1
fi

# On a desktop, drop --headless for the first run so you can complete
# the Facebook login / CAPTCHA in the visible browser window; the
# session is cached afterwards.
exec .venv/bin/ai-marketplace-monitor \
    --config config/bikes.toml \
    --config "$CREDENTIALS" \
    --headless \
    "$@"
