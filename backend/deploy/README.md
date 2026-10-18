# Deploying the Storybook API to an Ubuntu VPS (HTTPS)

Stack: **Caddy** (public `:80`/`:443`, automatic Let's Encrypt HTTPS) → **API**
(FastAPI/uvicorn, internal) → **Postgres 16** (internal). Only Caddy is exposed
to the internet.

Everything is driven by `deploy.sh <action>`. You run it on the VPS; nothing
here touches your server automatically. The API entrypoint **starts uvicorn
only** — migrations and reconciliation never run at container startup, so an
API restart cannot bypass the coordinated sequence below.

## Prerequisites

1. An Ubuntu VPS with a public IP and ports **80** and **443** reachable.
2. A domain you control. Add a DNS **A record** for the API hostname
   (e.g. `api.yourdomain.com`) pointing at the VPS IP. Let's Encrypt needs this
   resolvable *before* you deploy.
3. Ports 80/443 open in any firewall:
   ```bash
   sudo ufw allow 80,443/tcp   # if ufw is enabled
   ```
4. An **ElevenLabs API key**. `POST /v1/tts` proxies to ElevenLabs to narrate a scanned
   page; there is no default and no local fallback. Without a valid key that
   endpoint returns **502 on every request** while `/health`, the story list and
   TLS all stay green — so the break is invisible until someone scans a page on
   a device. Give the key text-to-speech access to the configured voice.

## Low-latency narration

ElevenLabs is the only speech provider. The default is `eleven_flash_v2_5`
(Vietnamese supported), with pooled HTTPS connections, style exaggeration and
speaker boost disabled, and 64-kbps MP3 output. Listen to Vietnamese, mixed-language
and numeric passages before rollout; Flash can sound different from v3 and number
normalization varies. Audio remains ephemeral and the ordered ZIP contract is unchanged.

Existing `.env` values override defaults. To activate the low-latency configuration,
set these explicitly in `backend/deploy/.env` before rebuilding/recreating the API:

```dotenv
ELEVENLABS_MODEL_ID=eleven_flash_v2_5
ELEVENLABS_OUTPUT_FORMAT=mp3_44100_64
ELEVENLABS_TTS_TIMEOUT_SECONDS=15
PAGE_AUDIO_CONCURRENCY=6
PAGE_AUDIO_PROCESS_CONCURRENCY=6
```

Keep your existing ElevenLabs key and voice ID. Concurrency is per process, not
deployment-wide; check the account's Flash limit before increasing it. A faster
model is not a one-second full-page guarantee. Measure `stage=audio_total`, which
includes queueing, all complete clips, and ZIP assembly (not OCR or client transfer).
Repeated text/language pairs are synthesized once per request, with no cross-request
cache. Historical specifications under `docs/superpowers` describe older providers;
use this guide and the current environment examples for deployment.

For an opt-in, paid benchmark of complete synthesis (13 distinct synthetic
Vietnamese lines, no saved text/audio), run from `backend`:

```bash
uv run python benchmark_page_audio.py --live --runs 3
```

This reports first and subsequent runs separately plus best/median/worst wall
time. It does not measure first-byte latency or claim that inference latency is
the time required to generate an entire page. In Docker, use
`docker compose -f docker-compose.prod.yml exec api python benchmark_page_audio.py --live --runs 3`
from `backend/deploy` to use the actual production settings and network location.

## Actions

```bash
cd app-book/backend/deploy

./deploy.sh deploy           # run the full release sequence below
./deploy.sh build            # build the API image only
./deploy.sh maintenance-up   # stop Caddy + API, keep the DB running
./deploy.sh migrate          # alembic upgrade head in a one-off API container
./deploy.sh api-up           # start only the API on the internal network
./deploy.sh reconcile        # backfill one privacy_settings row per user
./deploy.sh verify-internal  # API health + one-row check; Caddy stays down
./deploy.sh traffic-up       # start Caddy only
```

First run (with any action) creates `.env` with **generated secrets** and stops
so you can set the three values only you know:

```bash
nano .env        # DOMAIN=api.yourdomain.com, ACME_EMAIL=you@..., ELEVENLABS_API_KEY=...
./deploy.sh <action>   # run again — secrets are validated before every action
```

`deploy.sh` refuses to run any action while a secret is still a placeholder or
a dev default. A missing or unknown action prints usage and exits nonzero.

## Roll-forward release sequence

After updating the code (for example, with `git pull`), run the entire server
release with one command from `backend/deploy`:

```bash
./deploy.sh deploy
```

This runs `maintenance-up`, `build`, `migrate`, `api-up`, `reconcile`,
`verify-internal`, and `traffic-up` in order, stopping immediately if any step
fails. Public traffic is only resumed after verification succeeds.

Alternatively, run each action manually as shown below.

Run the actions **in this exact order**. Each step must succeed before the
next; if one fails, the server stays in maintenance mode until it is resolved.

```bash
cd app-book/backend/deploy

# 1. Maintenance: public traffic stops, DB keeps running
./deploy.sh maintenance-up

# 2. Build the new image (e.g. after a git pull)
git pull
./deploy.sh build

# 3. Migrate + backfill the DB with the new code
./deploy.sh migrate

# 4. Start the backend (internal network only, Caddy still down)
./deploy.sh api-up

# 5. Reconcile, then verify health + the one-row invariant — before any traffic
./deploy.sh reconcile
./deploy.sh verify-internal

# 6. Only now resume public API traffic
./deploy.sh traffic-up

# 7. Release the Flutter clients that require the new API
flutter build apk --dart-define=API_BASE_URL=https://api.yourdomain.com
flutter build ipa --dart-define=API_BASE_URL=https://api.yourdomain.com
```

Then start the retention job: first a **dry run** (reports candidates without
deleting anything), and only after reviewing its output **enable daily
retention** by scheduling the real run (e.g. host cron):

```bash
# dry run:
docker compose -f docker-compose.prod.yml run --rm api python privacy_retention.py --dry-run
# daily (crontab -e), real deletions:
15 4 * * * cd /path/to/app-book/backend/deploy && docker compose -f docker-compose.prod.yml run --rm api python privacy_retention.py
```

### No old-backend rollback after enforcement begins

Once the new backend is live and enforcement (consent gating, retention
deletes) has begun, **the safe response to a problem is maintenance mode
(`./deploy.sh maintenance-up`) plus a roll-forward** — fix forward with the
same sequence above. Do **not** roll back to the old backend image: the
database has already been migrated and reconciled, old code cannot serve the
new schema, and rolling back would bypass consent enforcement for data that is
now subject to it.

## Point the app at it

```bash
# Android
flutter build apk --dart-define=API_BASE_URL=https://api.yourdomain.com

# iOS
flutter build ipa --dart-define=API_BASE_URL=https://api.yourdomain.com

# or, to run on a connected device (either platform):
flutter run --dart-define=API_BASE_URL=https://api.yourdomain.com
```

No native changes are needed on either platform — the URL is HTTPS, which
Android permits by default and which satisfies iOS App Transport Security.

`API_BASE_URL` is not optional for a release build: `resolveApiBaseUrl()` throws
unless it is an explicit HTTPS URL with a non-loopback host.

## Adding narration audio later

The current stories fall back to TTS until real audio is registered.

```bash
# copy your clips (named aud_<segment_id>.m4a) to the host storage dir:
scp aud_*.m4a  user@vps:app-book/backend/storage/audio/
# then register them:
docker compose -f docker-compose.prod.yml exec -T api python register_assets.py
```

## Operations

```bash
COMPOSE="docker compose -f docker-compose.prod.yml"

$COMPOSE ps            # status
$COMPOSE logs -f api   # tail API logs
$COMPOSE logs -f caddy # TLS / cert issues show here
$COMPOSE restart api   # restart just the API (migrations do NOT run — by design)
$COMPOSE down          # stop everything (Postgres data + certs persist in volumes)
./deploy.sh build && ./deploy.sh migrate && ./deploy.sh api-up   # redeploy after a git pull
```

## Notes / limitations

- `.env` holds live secrets and is git-ignored — keep it on the server only.
- Postgres and the API have **no host port mappings**; reach the DB with
  `docker compose -f docker-compose.prod.yml exec db psql -U storybook`.
- This is a demo-grade single-node deployment: uvicorn single process, local
  filesystem for audio, no backups/monitoring. Fine for a product-owner demo;
  harden before real traffic.
