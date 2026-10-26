# Fb-scrape — used steel bike monitor

Persistent Facebook Marketplace monitor for a used drop-bar steel bike
search around Minneapolis, built on
[BoPeng/ai-marketplace-monitor](https://github.com/BoPeng/ai-marketplace-monitor)
**v0.10.2** (pinned; released 2026-07-17).

## Layout

| File | Purpose |
| --- | --- |
| `config/bikes.toml` | Search config — version controlled, no secrets. |
| `config/credentials.example.toml` | Template for the secrets file — committed. |
| `config/credentials.toml` | Your actual secrets — **gitignored, never committed**. |
| `run-monitor.sh` | Starts the monitor with both config files. |

The tool natively merges multiple `--config` files, which is what makes
the secrets split work. Note that `~/.ai-marketplace-monitor/config.toml`
is *always* read in addition if it exists — keep it empty so this repo
stays the single source of truth.

## Install (fresh machine)

Python 3.10+ required.

```bash
git clone https://github.com/pldalton1-source/Fb-scrape && cd Fb-scrape
python3 -m venv .venv
.venv/bin/pip install ai-marketplace-monitor==0.10.2
.venv/bin/playwright install chromium         # downloads the browser
# Linux only — system libraries for Chromium:
sudo .venv/bin/playwright install-deps chromium
```

(pipx also works: `pipx install ai-marketplace-monitor==0.10.2` then
`~/.local/pipx/venvs/ai-marketplace-monitor/bin/playwright install chromium` —
but the venv keeps tool + browser pinned together in one place.)

**Docker note:** on a headless Linux box or NAS, the official image
`ghcr.io/bopeng/ai-marketplace-monitor:latest` is the more reliable
route — it bundles Xvfb + Chromium + noVNC so you can solve Facebook
CAPTCHAs through the web UI's "Browser" button, which is the usual
failure point on machines with no display. On a desktop (macOS/Windows/
Linux with a GUI) the venv route above is simpler: run once *without*
`--headless`, log in interactively, and the session is cached.

## Credentials

```bash
cp config/credentials.example.toml config/credentials.toml
```

Then fill in the three placeholders (the example file has step-by-step
comments for each):

1. **Facebook**: your account email + password. With 2FA, complete the
   prompt in the browser window on first (non-headless) run.
2. **Pushover** (phone push): install the Pushover app, sign up at
   <https://pushover.net> — the dashboard shows *Your User Key*; then
   *Create an Application/API Token* for the API token. One-time $5 per
   platform after the 30-day trial.
3. **Anthropic API key** (Tier 2 AI screening only):
   <https://console.anthropic.com> → API Keys.

## Run

```bash
./run-monitor.sh                 # headless, for servers
# first run on a desktop — visible browser for login:
.venv/bin/ai-marketplace-monitor --config config/bikes.toml --config config/credentials.toml
```

A web UI for logs and live config editing starts at
<http://127.0.0.1:8467>.

### Verify a single listing (no waiting for a poll cycle)

Grab any real Marketplace bike listing URL and run:

```bash
.venv/bin/ai-marketplace-monitor \
    --config config/bikes.toml --config config/credentials.toml \
    --headless \
    --check 'https://www.facebook.com/marketplace/item/XXXXXXXXXXXXXXX/' \
    --for steel_drop_bar
```

It fetches that one listing and prints exactly why it was accepted or
rejected (price band, keywords/antikeywords, then the AI's rating with
its size-fit and tubing assessment). Use `--for macho_king` etc. to test
a Tier 1 rule instead; omit `--for` to be prompted.

### Run persistently (Linux, systemd user service)

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/bike-monitor.service <<'EOF'
[Unit]
Description=Facebook Marketplace bike monitor
After=network-online.target

[Service]
WorkingDirectory=%h/Fb-scrape
ExecStart=%h/Fb-scrape/run-monitor.sh
Restart=on-failure
RestartSec=60

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now bike-monitor
loginctl enable-linger "$USER"     # keep it running after logout
```

On macOS use a `launchd` plist or just keep it in a `tmux` session.

## What the search does

- **Region**: single Minneapolis anchor, `radius = 150` (miles for US
  accounts; Facebook's max is 500). One 150-mile radius already covers
  Duluth, St. Cloud, Rochester, Eau Claire, and La Crosse, so no
  separate city anchors are needed.
- **Tier 1** (12 blocks): one item per model with a tight used-market
  price band and a keyword anchor on the model name. `ai = []` disables
  AI screening — anything matching notifies immediately. Polled every
  **15–25 min**.
- **Tier 2** (`steel_drop_bar`): six broad phrases (gravel / cyclocross /
  steel road / all road / CX / Reynolds 853), $700–2200, antikeyword
  pre-filter for touring platforms, then Claude rates each listing 1–5
  against the size (54–56cm / M for 5'10") and tubing criteria; only
  **rating ≥ 4** notifies. Polled every **1–1.5 h**.

### The AI gate fails open

Worth knowing before trusting Tier 2: the monitor scores a listing **5**,
with the comment "Not evaluated by AI", whenever the AI call raises an
exception — and 5 clears the `rating = 4` threshold. An AI failure does
not quietly skip the listing, it pushes it as a top-rated match.

A missing `[ai.anthropic]` section does this, but so does an expired key,
an unfunded account, a rate limit, or a response the tool cannot parse.
If Tier 2 starts notifying on everything in the $700–2200 band, check the
log for

```
[AI] Failed to get an answer from anthropic:
```

before concluding the price band or antikeywords are wrong.

### Polling tradeoff

The scheduler technically allows a 1-second interval, but every cycle
here runs 17 Facebook searches (12 Tier 1 + 6 Tier 2 phrases, minus
overlap) plus a detail-page fetch per new listing, from a logged-in
account. Too aggressive and Facebook rate-limits, CAPTCHAs, or
checkpoints the account. 15–25 min for Tier 1 (~40–60 searches/hour)
with randomized jitter (`search_interval` → `max_search_interval`) is
about as hard as you can push a single residential-IP account without
regularly tripping checks; `sort_by = 'new'` plus the
`date_listed = last 24 hours` follow-up filter and the tool's seen-listing
cache keep each poll cheap. Tier 2 runs hourly because its broad phrases
return large result sets and each candidate costs an AI call. If you see
login checkpoints or CAPTCHA loops, back Tier 1 off to `30m`/`45m`.

## Price bands (Tier 1, editable in `config/bikes.toml`)

Macho King 500–1600 · Cosmic Stallion 800–2200 · Road Logic 800–2000 ·
Swiss Cross 800–2200 · Fog Cutter 600–1800 · Smoothie 400–1200 ·
Gunnar Sport 500–1500 · Hyper-X 500–1600 · Strael 1200–2800 ·
Roadhouse 500–1400 · Masi Speciale 300–1000 · Super Professional 600–1600
