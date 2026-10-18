#!/usr/bin/env bash
#
# Deploy the Interactive Storybook API to an Ubuntu VPS behind HTTPS (Caddy).
#
# Run this ON THE VPS, from backend/deploy, with exactly ONE action:
#     cd app-book/backend/deploy && ./deploy.sh <action>
#
# Actions:
#   build           Build the API image only (no containers started).
#   maintenance-up  Stop Caddy + API while keeping the DB running.
#   migrate         Run `alembic upgrade head` in a one-off API container.
#   api-up          Start only the API on the internal Compose network.
#   reconcile       Run privacy_reconcile.py in a one-off API container
#                   (backfills one privacy_settings row per user, verifies).
#   verify-internal Check API health and rerun the exact-one-row verification
#                   (count(users) == count(privacy_settings)). Caddy stays down.
#   traffic-up      Start Caddy only (public HTTPS traffic resumes).
#
# Every action first validates secrets/config in .env; nothing runs while a
# placeholder or dev-default secret remains.
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

usage() {
  cat >&2 <<EOF
Usage: ./deploy.sh <action>

Actions:
  build           Build the API image only
  maintenance-up  Stop Caddy + API, keep the DB running
  migrate         Run 'alembic upgrade head' in a one-off API container
  api-up          Start only the API on the internal network
  reconcile       Run privacy_reconcile.py in a one-off API container
  verify-internal Check API health + exact-one-row verification (Caddy stays down)
  traffic-up      Start Caddy only
EOF
}

compose() { docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"; }

# --- 1. Exactly one action argument ------------------------------------------
if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi
ACTION="$1"

# --- 2. Docker present? -------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Docker is not installed."
  read -rp "Install Docker Engine now via get.docker.com? [y/N] " ans
  [ "${ans:-N}" = "y" ] || [ "${ans:-N}" = "Y" ] || \
    die "Install Docker first: https://docs.docker.com/engine/install/ubuntu/"
  curl -fsSL https://get.docker.com | sh
  log "Docker installed. If 'docker' needs sudo, add yourself: sudo usermod -aG docker \$USER (then re-login)."
fi
docker compose version >/dev/null 2>&1 || die "The Docker Compose v2 plugin is required."

# --- 3. .env present? Create with generated secrets if not. -------------------
if [ ! -f "$ENV_FILE" ]; then
  log "No $ENV_FILE found — creating from $EXAMPLE_FILE with generated secrets."
  cp "$EXAMPLE_FILE" "$ENV_FILE"
  gen() { openssl rand -hex 32; }
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(gen)|"             "$ENV_FILE"
  sed -i "s|^ASSET_URL_SECRET=.*|ASSET_URL_SECRET=$(gen)|" "$ENV_FILE"
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(gen)|" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "Secrets generated into $ENV_FILE."
  die "Now edit $ENV_FILE — set DOMAIN, ACME_EMAIL and ELEVENLABS_API_KEY — then re-run ./deploy.sh <action>"
fi

# --- 4. Validate secrets/config (every action) --------------------------------
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
[ -n "${ELEVENLABS_API_KEY:-}" ] && [ "$ELEVENLABS_API_KEY" != "CHANGE_ME" ] || die "ELEVENLABS_API_KEY is unset or CHANGE_ME. Required for server narration. Get one at https://elevenlabs.io"

log "Config looks good. Running action: $ACTION"

# --- 5. Actions ---------------------------------------------------------------
case "$ACTION" in
  build)
    log "Building the API image (no containers started)..."
    compose build
    ;;

  maintenance-up)
    log "Entering maintenance: DB stays up, Caddy + API stop..."
    compose up -d db
    compose stop caddy api
    log "Maintenance mode. Public traffic is down; DB is running."
    ;;

  migrate)
    log "Running 'alembic upgrade head' in a one-off API container..."
    compose run --rm api alembic upgrade head
    ;;

  api-up)
    log "Starting the API on the internal Compose network (Caddy stays down)..."
    compose up -d api
    ;;

  reconcile)
    log "Running privacy_reconcile.py in a one-off API container..."
    compose run --rm api python privacy_reconcile.py
    ;;

  verify-internal)
    if compose ps --status running --services | grep -qx caddy; then
      die "verify-internal requires Caddy to be stopped. Run './deploy.sh maintenance-up' first."
    fi
    log "Waiting for the API to become healthy (internal only)..."
    for i in $(seq 1 45); do
      if compose exec -T api python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" >/dev/null 2>&1; then
        log "API is healthy."
        break
      fi
      [ "$i" = "45" ] && die "API did not become healthy. Check logs: docker compose -f $COMPOSE_FILE logs api"
      sleep 2
    done
    log "Verifying exactly one privacy_settings row per user..."
    compose exec -T api python -c "
import sys
from sqlalchemy import func, select
from app.db import SessionLocal
from app.models import PrivacySettings, User
db = SessionLocal()
try:
    users = db.scalar(select(func.count()).select_from(User))
    rows = db.scalar(select(func.count()).select_from(PrivacySettings))
finally:
    db.close()
print(f'users={users} privacy_rows={rows}')
sys.exit(0 if users == rows else 1)
"
    log "Verification passed and Caddy is down. Resume traffic with: ./deploy.sh traffic-up"
    ;;

  traffic-up)
    log "Starting Caddy only (API must already be up and verified)..."
    compose up -d caddy
    log "Public traffic resumed at: https://${DOMAIN}"
    ;;

  *)
    usage
    die "Unknown action: $ACTION"
    ;;
esac
