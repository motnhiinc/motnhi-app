# syntax=docker/dockerfile:1
#
# Interactive Storybook API image.
#
# IMPORTANT: the build context is the REPO ROOT (not backend/), because
# seed.py reads the seed JSON from ../assets/data — i.e. one level above
# backend/. See docker-compose.prod.yml `build.context: ../..`.
FROM python:3.12-slim

# uv — fast, reproducible installs from uv.lock. Bump the tag to upgrade uv.
COPY --from=ghcr.io/astral-sh/uv:0.5 /uv /uvx /bin/

ENV UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/app/.venv \
    PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

WORKDIR /app

# 1) Dependency layer — cached unless pyproject/uv.lock change.
#    --no-install-project: this is an app, not a packaged library (no build backend).
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

# 2) Application code.
COPY backend/ ./

# 3) Seed JSON at the exact path seed.py expects:
#    /app/seed.py -> parent.parent == / -> /assets/data
COPY assets/data/ /assets/data/

# 4) Entrypoint: run migrations, then serve.
COPY backend/deploy/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
