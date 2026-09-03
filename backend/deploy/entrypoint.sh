#!/bin/sh
# API container entrypoint.
#
# With no arguments: start the server. Database migrations are NOT run here —
# startup migration would let an API restart bypass the coordinated maintenance
# sequence (see README.md). Run migrations explicitly, e.g.:
#     docker compose -f docker-compose.prod.yml run --rm api alembic upgrade head
#
# With arguments: exec them instead. This makes one-off commands work despite
# the image ENTRYPOINT, e.g.:
#     docker compose run --rm api alembic upgrade head
#     docker compose run --rm api python privacy_reconcile.py
set -e

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

echo "[entrypoint] starting API on :8000..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
