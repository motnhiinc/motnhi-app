#!/bin/sh
# API container entrypoint: apply DB migrations, then start the server.
# The db service is gated behind a healthcheck (depends_on: service_healthy),
# so Postgres is reachable by the time this runs. `alembic upgrade head` is
# idempotent — safe on every (re)start.
set -e

echo "[entrypoint] applying database migrations..."
alembic upgrade head

echo "[entrypoint] starting API on :8000..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
