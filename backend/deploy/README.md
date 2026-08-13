# Deploying the Storybook API to an Ubuntu VPS (HTTPS)

Stack: **Caddy** (public `:80`/`:443`, automatic Let's Encrypt HTTPS) → **API**
(FastAPI/uvicorn, internal) → **Postgres 16** (internal). Only Caddy is exposed
to the internet.

Everything is driven by `deploy.sh`. You run it on the VPS; nothing here
touches your server automatically.

## Prerequisites

1. An Ubuntu VPS with a public IP and ports **80** and **443** reachable.
2. A domain you control. Add a DNS **A record** for the API hostname
   (e.g. `api.yourdomain.com`) pointing at the VPS IP. Let's Encrypt needs this
   resolvable *before* you deploy.
3. Ports 80/443 open in any firewall:
   ```bash
   sudo ufw allow 80,443/tcp   # if ufw is enabled
   ```

## Steps

```bash
# On the VPS
git clone <your-repo-url> app-book
cd app-book/backend/deploy

./deploy.sh
```

First run creates `.env` with **generated secrets** and stops so you can set the
two values only you know:

```bash
nano .env        # set DOMAIN=api.yourdomain.com and ACME_EMAIL=you@...
./deploy.sh      # run again — builds, starts, waits for health, seeds stories
```

When it finishes:

```bash
curl -sS https://api.yourdomain.com/health   # -> {"status":"ok"}
```

## Point the Android app at it

```bash
flutter build apk --dart-define=API_BASE_URL=https://api.yourdomain.com
# or, to run on a connected device:
flutter run --dart-define=API_BASE_URL=https://api.yourdomain.com
```

No Android native changes are needed — the URL is HTTPS, which Android permits
by default.

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
$COMPOSE restart api   # restart just the API
$COMPOSE down          # stop everything (Postgres data + certs persist in volumes)
$COMPOSE up -d --build # redeploy after a git pull
```

## Notes / limitations

- `.env` holds live secrets and is git-ignored — keep it on the server only.
- Postgres and the API have **no host port mappings**; reach the DB with
  `docker compose -f docker-compose.prod.yml exec db psql -U storybook`.
- This is a demo-grade single-node deployment: uvicorn single process, local
  filesystem for audio, no backups/monitoring. Fine for a product-owner demo;
  harden before real traffic.
