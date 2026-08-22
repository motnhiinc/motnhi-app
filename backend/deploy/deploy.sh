#!/usr/bin/env bash
#
# Deploy the Interactive Storybook API to an Ubuntu VPS behind HTTPS (Caddy).
#
# Run this ON THE VPS, after cloning the repo, from backend/deploy:
#     cd app-book/backend/deploy && ./deploy.sh
#
# It will:
#   1. Ensure Docker is installed (offers to install on Ubuntu).
#   2. Create ./.env with generated secrets if missing, then stop so you can
#      set DOMAIN + ACME_EMAIL + OPENAI_API_KEY.
#   3. Refuse to run with dev-default / placeholder secrets.
#   4. Build and start caddy + api + db.
#   5. Wait for the API to become healthy.
#   6. Seed the 5 stories (idempotent).
set -euo pipefail

cd "$(dirname "$0")" # -> backend/deploy

COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env"
EXAMPLE_FILE=".env.production.example"

# Known values that must NEVER reach production.
DEV_JWT="dev-only-not-for-prod-0123456789abcdef0123456789abcdef"
DEV_ASSET="dev-asset-secret-0123456789abcdef0123456789abcdef"

log()  { printf '\033[1;36m[deploy]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[deploy] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

compose() { docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"; }

# --- 1. Docker present? -------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Docker is not installed."
  read -rp "Install Docker Engine now via get.docker.com? [y/N] " ans
  [ "${ans:-N}" = "y" ] || [ "${ans:-N}" = "Y" ] || \
    die "Install Docker first: https://docs.docker.com/engine/install/ubuntu/"
  curl -fsSL https://get.docker.com | sh
  log "Docker installed. If 'docker' needs sudo, add yourself: sudo usermod -aG docker \$USER (then re-login)."
fi
docker compose version >/dev/null 2>&1 || die "The Docker Compose v2 plugin is required."

# --- 2. .env present? Create with generated secrets if not. -------------------
if [ ! -f "$ENV_FILE" ]; then
  log "No $ENV_FILE found — creating from $EXAMPLE_FILE with generated secrets."
  cp "$EXAMPLE_FILE" "$ENV_FILE"
  gen() { openssl rand -hex 32; }
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(gen)|"             "$ENV_FILE"
  sed -i "s|^ASSET_URL_SECRET=.*|ASSET_URL_SECRET=$(gen)|" "$ENV_FILE"
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(gen)|" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "Secrets generated into $ENV_FILE."
  die "Now edit $ENV_FILE — set DOMAIN, ACME_EMAIL and OPENAI_API_KEY — then re-run ./deploy.sh"
fi

# --- 3. Validate secrets/config ----------------------------------------------
# Lock down perms regardless of how .env got here (auto-generated or manual cp).
chmod 600 "$ENV_FILE"
set -a; . "./$ENV_FILE"; set +a

[ -n "${DOMAIN:-}" ]     && [ "$DOMAIN" != "api.example.com" ] || die "Set a real DOMAIN in $ENV_FILE (has an A record to this VPS)."
[ -n "${ACME_EMAIL:-}" ] && [ "$ACME_EMAIL" != "you@example.com" ] || die "Set a real ACME_EMAIL in $ENV_FILE."
[ -n "${JWT_SECRET:-}" ]        && [ "$JWT_SECRET" != "$DEV_JWT" ]     && [ "$JWT_SECRET" != "CHANGE_ME" ]     || die "JWT_SECRET is unset, dev-default, or CHANGE_ME. Generate: openssl rand -hex 32"
[ -n "${ASSET_URL_SECRET:-}" ]  && [ "$ASSET_URL_SECRET" != "$DEV_ASSET" ] && [ "$ASSET_URL_SECRET" != "CHANGE_ME" ] || die "ASSET_URL_SECRET is unset, dev-default, or CHANGE_ME. Generate: openssl rand -hex 32"
[ -n "${POSTGRES_PASSWORD:-}" ] && [ "$POSTGRES_PASSWORD" != "CHANGE_ME" ] || die "POSTGRES_PASSWORD is unset or CHANGE_ME. Generate: openssl rand -hex 32"
# Unlike the secrets above this one cannot be generated — it is an external
# credential. Checked here so a bad deploy fails now, not silently at /v1/tts.
[ -n "${OPENAI_API_KEY:-}" ]    && [ "$OPENAI_API_KEY" != "CHANGE_ME" ] || die "OPENAI_API_KEY is unset or CHANGE_ME. Required by POST /v1/tts (scan-any-page narration); there is no default. Get one at https://platform.openai.com/api-keys"

log "Config looks good. Deploying to https://${DOMAIN}"

# --- 4. Build + start --------------------------------------------------------
log "Building and starting containers (this can take a few minutes first time)..."
compose up -d --build

# --- 5. Wait for API health --------------------------------------------------
log "Waiting for the API to become healthy..."
for i in $(seq 1 45); do
  if compose exec -T api python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" >/dev/null 2>&1; then
    log "API is healthy."
    break
  fi
  [ "$i" = "45" ] && die "API did not become healthy. Check logs: docker compose -f $COMPOSE_FILE logs api"
  sleep 2
done

# --- 6. Seed content (idempotent: seed.py uses db.merge) ----------------------
log "Seeding stories..."
compose exec -T api python seed.py

log "-----------------------------------------------------------------"
log "Done. API live at:  https://${DOMAIN}"
log "Smoke test:         curl -sS https://${DOMAIN}/health"
log "Build the Android app against it:"
printf '   flutter build apk --dart-define=API_BASE_URL=https://%s\n' "$DOMAIN"
log "(Later) add narration audio: scp *.m4a to backend/storage/audio, then:"
printf '   docker compose -f %s exec -T api python register_assets.py\n' "$COMPOSE_FILE"
