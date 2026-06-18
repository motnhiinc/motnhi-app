# Backend API (Client-Contract Slice) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a Python/FastAPI + Postgres backend serving exactly the endpoints the existing Flutter client consumes, and swap the client's repositories from bundled-local to HTTP — with no UI changes.

**Architecture:** Layered FastAPI service (routers → repositories → SQLAlchemy 2.0 ORM, Pydantic v2 at the edges). Anonymous device auth: a client device id is exchanged for a JWT scoping a provisioned `users` row. The 5 bundled `assets/data/*.json` files are the seed data AND the contract-test oracle. On the client, the abstract repository interfaces are unchanged; new `Http*` implementations replace the `Local*` ones via DI override.

**Tech Stack:** Python 3.12, FastAPI, Pydantic v2, SQLAlchemy 2.0, Alembic, PyJWT, pytest + FastAPI TestClient, Postgres (Docker Compose), `uv`. Client: `dio` + `http_mock_adapter` (dev).

**Spec:** `docs/superpowers/specs/2026-06-17-backend-api-design.md`

---

## Modeling notes (consequences of spec §4, apply throughout)

- **Content tables use `TEXT` primary keys** (`stories`, `story_pages`, `narration_segments`, `ar_scenes`, `questions`, `question_choices`) to preserve the content's natural ids (`story_bunny_forest`, `seg_bunny_p3_owl`, `q_bunny_01`, `a_moon`) the client requests by.
- **Runtime tables use server-generated UUID strings** (`users`, `devices`, `story_sessions`, `interaction_events`), stored as `TEXT` for uniformity.
- **`child_profiles.id` is client-provided** (the onboarding-generated UUID), upserted; `user_id` is taken from the JWT, never the body.
- All timestamps are timezone-aware UTC ISO-8601 strings on the wire (`started_at`, `created_at`, …), matching the client's `DateTime` parsing.
- `is_unlocked` is always `true` (entitlements deferred); `is_downloaded` is always `false` from the server (client owns download state).

---

## File structure

```
backend/
  pyproject.toml              # uv project + deps
  docker-compose.yml          # local + test Postgres
  alembic.ini
  .env.example
  app/
    __init__.py
    config.py                 # Settings (pydantic-settings)
    db.py                     # engine, SessionLocal, Base, get_db
    auth.py                   # JWT issue/verify, get_current_user dep
    main.py                   # FastAPI app + router registration
    models/__init__.py        # all ORM models (§10 + extensions)
    schemas/__init__.py       # all Pydantic DTOs
    repositories/
      __init__.py
      stories.py
      profiles.py
      sessions.py
    routers/
      __init__.py
      auth.py
      stories.py
      profiles.py
      sessions.py
  migrations/                 # Alembic env + versions
  seed.py                     # ingest ../assets/data/*.json
  tests/
    conftest.py
    test_auth.py
    test_stories.py
    test_profiles.py
    test_sessions.py
    test_contract.py

lib/data/sources/api_client.dart          # NEW dio wrapper + auth interceptor
lib/data/repositories/http_story_repository.dart      # NEW
lib/data/repositories/http_profile_repository.dart    # NEW
lib/data/repositories/http_session_repository.dart    # NEW
lib/core/di.dart                            # MODIFY: wire Http* repos
test/http_repositories_test.dart           # NEW client unit tests
pubspec.yaml                                # MODIFY: add dio + http_mock_adapter
```

---

## PHASE A — Backend foundation

### Task 1: Backend project scaffold

**Files:**
- Create: `backend/pyproject.toml`
- Create: `backend/docker-compose.yml`
- Create: `backend/.env.example`
- Create: `backend/app/__init__.py` (empty)
- Create: `backend/app/config.py`
- Create: `backend/app/main.py`

- [ ] **Step 1: Create `backend/pyproject.toml`**

```toml
[project]
name = "storybook-backend"
version = "0.1.0"
description = "Interactive Storybook backend — client-contract slice"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.115",
    "uvicorn[standard]>=0.30",
    "sqlalchemy>=2.0",
    "psycopg[binary]>=3.2",
    "alembic>=1.13",
    "pydantic>=2.7",
    "pydantic-settings>=2.3",
    "pyjwt>=2.8",
]

[dependency-groups]
dev = [
    "pytest>=8.2",
    "httpx>=0.27",
]

[tool.pytest.ini_options]
pythonpath = ["."]
testpaths = ["tests"]
```

- [ ] **Step 2: Create `backend/docker-compose.yml`**

```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: storybook
      POSTGRES_PASSWORD: storybook
      POSTGRES_DB: storybook
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata:
```

- [ ] **Step 3: Create `backend/.env.example`**

```bash
DATABASE_URL=postgresql+psycopg://storybook:storybook@localhost:5432/storybook
TEST_DATABASE_URL=postgresql+psycopg://storybook:storybook@localhost:5432/storybook_test
JWT_SECRET=dev-secret-change-me
```

- [ ] **Step 4: Create `backend/app/config.py`**

```python
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://storybook:storybook@localhost:5432/storybook"
    test_database_url: str = "postgresql+psycopg://storybook:storybook@localhost:5432/storybook_test"
    jwt_secret: str = "dev-secret-change-me"
    jwt_algorithm: str = "HS256"


settings = Settings()
```

- [ ] **Step 5: Create `backend/app/main.py` (routers added in later tasks)**

```python
from fastapi import FastAPI

app = FastAPI(title="Interactive Storybook API", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
```

- [ ] **Step 6: Install deps and verify the app imports**

Run:
```bash
cd backend && uv sync && uv run python -c "from app.main import app; print('ok')"
```
Expected: prints `ok` (after uv resolves the environment).

- [ ] **Step 7: Commit**

```bash
git add backend/pyproject.toml backend/docker-compose.yml backend/.env.example backend/app/__init__.py backend/app/config.py backend/app/main.py backend/uv.lock
git commit -m "feat(backend): project scaffold (FastAPI + uv + compose)"
```

---

### Task 2: Database engine, session, and Base

**Files:**
- Create: `backend/app/db.py`

- [ ] **Step 1: Create `backend/app/db.py`**

```python
from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings

engine = create_engine(settings.database_url, future=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

- [ ] **Step 2: Verify import**

Run: `cd backend && uv run python -c "from app.db import Base, engine, get_db; print('ok')"`
Expected: prints `ok`

- [ ] **Step 3: Commit**

```bash
git add backend/app/db.py
git commit -m "feat(backend): db engine, session, declarative base"
```

---

### Task 3: ORM models (§10 + extensions)

**Files:**
- Create: `backend/app/models/__init__.py`

- [ ] **Step 1: Create `backend/app/models/__init__.py`**

```python
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


# ---- runtime tables (server-generated UUID strings) ----
class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    email: Mapped[str | None] = mapped_column(Text, unique=True, nullable=True)
    auth_provider: Mapped[str] = mapped_column(Text, default="device")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Device(Base):
    __tablename__ = "devices"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    device_id: Mapped[str] = mapped_column(Text, unique=True, index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class ChildProfile(Base):
    __tablename__ = "child_profiles"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    nickname: Mapped[str | None] = mapped_column(Text, nullable=True)
    age_band: Mapped[str] = mapped_column(Text)
    language_code: Mapped[str] = mapped_column(Text, default="en")
    bedtime_mode_default: Mapped[bool] = mapped_column(Boolean, default=False)
    microphone_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    ar_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class StorySession(Base):
    __tablename__ = "story_sessions"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    child_profile_id: Mapped[str] = mapped_column(ForeignKey("child_profiles.id"), index=True)
    story_id: Mapped[str] = mapped_column(ForeignKey("stories.id"))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_page_number: Mapped[int] = mapped_column(Integer, default=0)
    mode: Mapped[str] = mapped_column(Text, default="library")


class InteractionEvent(Base):
    __tablename__ = "interaction_events"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    story_session_id: Mapped[str] = mapped_column(ForeignKey("story_sessions.id"), index=True)
    event_type: Mapped[str] = mapped_column(Text)
    page_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    payload: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


# ---- content tables (TEXT natural ids, from seed) ----
class Story(Base):
    __tablename__ = "stories"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    title: Mapped[str] = mapped_column(Text)
    slug: Mapped[str] = mapped_column(Text, unique=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    age_min: Mapped[int] = mapped_column(Integer, default=3)
    age_max: Mapped[int] = mapped_column(Integer, default=8)
    language_code: Mapped[str] = mapped_column(Text, default="en")
    duration_seconds: Mapped[int] = mapped_column(Integer, default=0)
    cover_asset_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    content_status: Mapped[str] = mapped_column(Text, default="published")
    rights_owner_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    themes: Mapped[list] = mapped_column(JSONB, default=list)

    pages: Mapped[list["StoryPage"]] = relationship(cascade="all, delete-orphan")
    segments: Mapped[list["NarrationSegment"]] = relationship(cascade="all, delete-orphan")
    ar_scenes: Mapped[list["ArScene"]] = relationship(cascade="all, delete-orphan")
    questions: Mapped[list["Question"]] = relationship(cascade="all, delete-orphan")


class StoryPage(Base):
    __tablename__ = "story_pages"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    story_id: Mapped[str] = mapped_column(ForeignKey("stories.id"), index=True)
    page_number: Mapped[int] = mapped_column(Integer)
    page_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    page_image_asset_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_target_id: Mapped[str | None] = mapped_column(Text, nullable=True)


class NarrationSegment(Base):
    __tablename__ = "narration_segments"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    story_id: Mapped[str] = mapped_column(ForeignKey("stories.id"), index=True)
    page_id: Mapped[str] = mapped_column(ForeignKey("story_pages.id"), index=True)
    speaker_key: Mapped[str] = mapped_column(Text)
    text: Mapped[str] = mapped_column(Text)
    voice_id: Mapped[str] = mapped_column(Text)
    emotion: Mapped[str | None] = mapped_column(Text, nullable=True)
    speed: Mapped[float | None] = mapped_column(Numeric(4, 2), nullable=True)
    audio_asset_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    start_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    end_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer)


class ArScene(Base):
    __tablename__ = "ar_scenes"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    story_id: Mapped[str] = mapped_column(ForeignKey("stories.id"), index=True)
    page_id: Mapped[str] = mapped_column(ForeignKey("story_pages.id"), index=True)
    scene_json: Mapped[dict] = mapped_column(JSONB)
    status: Mapped[str] = mapped_column(Text, default="published")


class Question(Base):
    __tablename__ = "questions"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    story_id: Mapped[str] = mapped_column(ForeignKey("stories.id"), index=True)
    page_id: Mapped[str] = mapped_column(ForeignKey("story_pages.id"))
    type: Mapped[str] = mapped_column(Text)
    prompt: Mapped[str] = mapped_column(Text)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    choices: Mapped[list["QuestionChoice"]] = relationship(cascade="all, delete-orphan")


class QuestionChoice(Base):
    __tablename__ = "question_choices"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    question_id: Mapped[str] = mapped_column(ForeignKey("questions.id"), index=True)
    label: Mapped[str] = mapped_column(Text)
    emoji: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_correct: Mapped[bool] = mapped_column(Boolean, default=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
```

- [ ] **Step 2: Verify all models import and register on Base**

Run: `cd backend && uv run python -c "import app.models; from app.db import Base; print(sorted(Base.metadata.tables))"`
Expected: a list containing all 11 table names.

- [ ] **Step 3: Commit**

```bash
git add backend/app/models/__init__.py
git commit -m "feat(backend): ORM models (§10 tables + questions/devices extensions)"
```

---

### Task 4: Alembic initial migration

**Files:**
- Create: `backend/alembic.ini`
- Create: `backend/migrations/env.py`
- Create: `backend/migrations/script.py.mako`
- Create: `backend/migrations/versions/0001_initial.py` (autogenerated, then committed)

- [ ] **Step 1: Initialize Alembic scaffolding**

Run: `cd backend && uv run alembic init migrations`
Then edit `backend/alembic.ini` — set:
```ini
sqlalchemy.url =
```
(leave empty; the URL is injected in `env.py`).

- [ ] **Step 2: Wire `backend/migrations/env.py` to our metadata and URL**

Replace the generated `env.py` body's config section so it reads:
```python
from app.config import settings
from app.db import Base
import app.models  # noqa: F401  (registers tables on Base.metadata)

config = context.config
config.set_main_option("sqlalchemy.url", settings.database_url)
target_metadata = Base.metadata
```
(Keep the rest of Alembic's generated `run_migrations_online/offline` functions.)

- [ ] **Step 3: Start Postgres and autogenerate the migration**

Run:
```bash
cd backend && docker compose up -d db && sleep 3
uv run alembic revision --autogenerate -m "initial schema"
```
Expected: a new file under `migrations/versions/` creating all 11 tables. Rename it to `0001_initial.py` for clarity.

- [ ] **Step 4: Apply and verify the migration**

Run: `cd backend && uv run alembic upgrade head`
Then: `uv run python -c "from sqlalchemy import inspect; from app.db import engine; print(sorted(inspect(engine).get_table_names()))"`
Expected: all 11 tables plus `alembic_version`.

- [ ] **Step 5: Commit**

```bash
git add backend/alembic.ini backend/migrations
git commit -m "feat(backend): alembic initial schema migration"
```

---

### Task 5: Seed script (ingest the 5 bundled stories)

**Files:**
- Create: `backend/seed.py`

- [ ] **Step 1: Create `backend/seed.py`**

```python
"""Ingest assets/data/*.json into the content tables.

The bundled story JSON is the source of truth (spec §4): one manifest listing
slugs, one detail file per slug shaped exactly like GET /v1/stories/{id}.
"""
import json
from pathlib import Path

from sqlalchemy.orm import Session

from app.db import SessionLocal
from app.models import (
    ArScene,
    NarrationSegment,
    Question,
    QuestionChoice,
    Story,
    StoryPage,
)

DATA_DIR = Path(__file__).resolve().parent.parent / "assets" / "data"


def seed_story(db: Session, detail: dict) -> None:
    s = detail["story"]
    db.merge(Story(
        id=s["id"], title=s["title"], slug=s["slug"], description=s.get("description"),
        age_min=s.get("age_min", 3), age_max=s.get("age_max", 8),
        language_code=s.get("language_code", "en"),
        duration_seconds=s.get("duration_seconds", 0),
        cover_asset_id=s.get("cover_asset_id"), content_status=s.get("content_status", "published"),
        rights_owner_id=s.get("rights_owner_id"), themes=s.get("themes", []),
    ))
    for p in detail.get("pages", []):
        db.merge(StoryPage(
            id=p["id"], story_id=p["story_id"], page_number=p["page_number"],
            page_text=p.get("page_text"), page_image_asset_id=p.get("page_image_asset_id"),
            image_target_id=p.get("image_target_id"),
        ))
    for seg in detail.get("segments", []):
        db.merge(NarrationSegment(
            id=seg["id"], story_id=seg["story_id"], page_id=seg["page_id"],
            speaker_key=seg["speaker_key"], text=seg["text"], voice_id=seg["voice_id"],
            emotion=seg.get("emotion"), speed=seg.get("speed"),
            audio_asset_id=seg.get("audio_asset_id"),
            start_ms=seg.get("start_ms"), end_ms=seg.get("end_ms"), sort_order=seg["sort_order"],
        ))
    for scene in detail.get("ar_scenes", []):
        db.merge(ArScene(
            id=scene["id"], story_id=scene["story_id"], page_id=scene["page_id"],
            scene_json=scene["scene_json"], status=scene.get("status", "published"),
        ))
    for qi, q in enumerate(detail.get("questions", [])):
        db.merge(Question(
            id=q["id"], story_id=s["id"], page_id=q["page_id"],
            type=q["type"], prompt=q["prompt"], sort_order=qi,
        ))
        for ci, c in enumerate(q.get("choices", [])):
            db.merge(QuestionChoice(
                id=c["id"], question_id=q["id"], label=c["label"], emoji=c.get("emoji"),
                is_correct=c.get("is_correct", False), sort_order=ci,
            ))


def seed_all(db: Session, data_dir: Path = DATA_DIR) -> int:
    manifest = json.loads((data_dir / "manifest.json").read_text())
    slugs = manifest["stories"]
    for slug in slugs:
        detail = json.loads((data_dir / f"{slug}.json").read_text())
        seed_story(db, detail)
    db.commit()
    return len(slugs)


if __name__ == "__main__":
    db = SessionLocal()
    try:
        count = seed_all(db)
        print(f"seeded {count} stories")
    finally:
        db.close()
```

- [ ] **Step 2: Run the seed against the migrated DB**

Run: `cd backend && uv run python seed.py`
Expected: prints `seeded 5 stories`.

- [ ] **Step 3: Verify content landed**

Run: `cd backend && uv run python -c "from app.db import SessionLocal; from app.models import Story, Question; db=SessionLocal(); print(db.query(Story).count(), db.query(Question).count())"`
Expected: `5 <N>` where N ≥ 3 (Bunny alone has 3 questions).

- [ ] **Step 4: Commit**

```bash
git add backend/seed.py
git commit -m "feat(backend): seed script ingesting bundled story JSON"
```

---

## PHASE B — Backend auth

> ### 🔒 SECURITY AMENDMENT (device_secret) — supersedes the auth code below
>
> A security review flagged that minting a token from a client-asserted `device_id`
> alone has no proof-of-possession (anyone who learns a `device_id` can take over
> that device's user). Decision: add a server-generated `device_secret`. This
> amendment **supersedes** the relevant snippets in Tasks 6/7 (and Task 13). Net
> changes:
>
> 1. **`models` — `Device` gains a non-null `secret_hash`:**
>    `secret_hash: Mapped[str] = mapped_column(Text)`  → requires a new Alembic
>    migration `0002_device_secret` (`uv run alembic revision --autogenerate -m "device secret"` then `upgrade head`). The test harness uses `create_all`, so tests pick it up automatically.
>
> 2. **`app/auth.py` — add secret helpers; shorten JWT to 30 days:**
>    ```python
>    import hashlib, hmac, secrets
>
>    def generate_secret() -> str:
>        return secrets.token_urlsafe(32)
>
>    def hash_secret(secret: str) -> str:
>        return hashlib.sha256(secret.encode()).hexdigest()
>
>    def verify_secret(secret: str, secret_hash: str) -> bool:
>        return hmac.compare_digest(hash_secret(secret), secret_hash)
>    ```
>    In `create_token`, change `timedelta(days=365)` → `timedelta(days=30)`.
>    (SHA-256 without a slow KDF is appropriate here: the secret is a 256-bit
>    random token, not a low-entropy password.)
>
> 3. **`schemas` — request carries optional secret; response returns it once:**
>    ```python
>    class DeviceAuthRequest(BaseModel):
>        device_id: str
>        device_secret: str | None = None
>
>    class DeviceAuthResponse(BaseModel):
>        token: str
>        user_id: str
>        device_secret: str | None = None  # set ONLY on first registration
>    ```
>
> 4. **`routers/auth.py` — register-or-verify:**
>    ```python
>    @router.post("/device", response_model=DeviceAuthResponse)
>    def device_auth(body: DeviceAuthRequest, db: Session = Depends(get_db)) -> DeviceAuthResponse:
>        device = db.scalar(select(Device).where(Device.device_id == body.device_id))
>        if device is None:
>            now = datetime.now(timezone.utc)
>            secret = generate_secret()
>            user = User(id=str(uuid.uuid4()), auth_provider="device", created_at=now, updated_at=now)
>            db.add(user)
>            db.flush()
>            device = Device(id=str(uuid.uuid4()), device_id=body.device_id, user_id=user.id,
>                            secret_hash=hash_secret(secret), created_at=now)
>            db.add(device)
>            db.commit()
>            return DeviceAuthResponse(token=create_token(user.id), user_id=user.id, device_secret=secret)
>        if not body.device_secret or not verify_secret(body.device_secret, device.secret_hash):
>            raise HTTPException(status_code=401, detail="invalid device credentials")
>        return DeviceAuthResponse(token=create_token(device.user_id), user_id=device.user_id)
>    ```
>    (add `HTTPException` to the FastAPI import and `generate_secret, hash_secret, verify_secret` to the auth import.)
>
> 5. **`tests/test_auth.py` — replace the idempotency test:**
>    ```python
>    def test_device_auth_registers_then_requires_secret(client):
>        first = client.post("/v1/auth/device", json={"device_id": "device-abc"})
>        assert first.status_code == 200
>        body = first.json()
>        assert body["token"] and body["user_id"] and body["device_secret"]
>
>        again = client.post("/v1/auth/device",
>                            json={"device_id": "device-abc", "device_secret": body["device_secret"]})
>        assert again.status_code == 200
>        assert again.json()["user_id"] == body["user_id"]
>        assert again.json()["device_secret"] is None
>
>        assert client.post("/v1/auth/device", json={"device_id": "device-abc"}).status_code == 401
>        assert client.post("/v1/auth/device",
>                           json={"device_id": "device-abc", "device_secret": "wrong"}).status_code == 401
>    ```
>    Other tests/routers that bootstrap auth (stories/profiles/sessions test helpers) call
>    `/v1/auth/device` once per device id and use the returned token — they keep working,
>    since first-registration still returns a token. Only re-auth of an existing device needs the secret.

### Task 6: Device JWT issue/verify + current-user dependency

**Files:**
- Create: `backend/app/auth.py`
- Test: `backend/tests/conftest.py`, `backend/tests/test_auth.py`

- [ ] **Step 1: Create `backend/tests/conftest.py` (transactional test DB + client)**

```python
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.config import settings
from app.db import Base, get_db
from app.main import app
import app.models  # noqa: F401

engine = create_engine(settings.test_database_url, future=True)
TestingSessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


@pytest.fixture(scope="session", autouse=True)
def _schema():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    yield
    Base.metadata.drop_all(engine)


@pytest.fixture
def db():
    connection = engine.connect()
    trans = connection.begin()
    session = TestingSessionLocal(bind=connection)
    yield session
    session.close()
    trans.rollback()
    connection.close()


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
```

- [ ] **Step 2: Write the failing test `backend/tests/test_auth.py`**

```python
import pytest

from app.auth import create_token, decode_token


def test_token_roundtrip():
    token = create_token("user-123")
    assert decode_token(token) == "user-123"


def test_decode_rejects_garbage():
    with pytest.raises(Exception):
        decode_token("not-a-jwt")
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd backend && uv run pytest tests/test_auth.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'app.auth'` (or ImportError).

- [ ] **Step 4: Create `backend/app/auth.py`**

```python
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.models import User


def create_token(user_id: str) -> str:
    payload = {
        "sub": user_id,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + timedelta(days=365),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> str:
    data = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    return data["sub"]


def get_current_user(
    authorization: str = Header(default=""),
    db: Session = Depends(get_db),
) -> User:
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    try:
        user_id = decode_token(authorization.removeprefix("Bearer "))
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="invalid token")
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="unknown user")
    return user
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && uv run pytest tests/test_auth.py -v`
Expected: PASS (2 passed). Requires the test DB to exist — create it once with `docker compose exec db createdb -U storybook storybook_test` (ignore error if it already exists).

- [ ] **Step 6: Commit**

```bash
git add backend/app/auth.py backend/tests/conftest.py backend/tests/test_auth.py
git commit -m "feat(backend): device JWT issue/verify + current-user dep"
```

---

### Task 7: Auth router — POST /v1/auth/device

**Files:**
- Create: `backend/app/schemas/__init__.py` (auth schemas; extended in Task 8)
- Create: `backend/app/routers/__init__.py` (empty)
- Create: `backend/app/routers/auth.py`
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_auth.py`

- [ ] **Step 1: Add the failing endpoint test to `backend/tests/test_auth.py`**

```python
def test_device_auth_provisions_user_and_returns_token(client):
    resp = client.post("/v1/auth/device", json={"device_id": "device-abc"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["user_id"]
    assert body["token"]

    # same device id -> same user (idempotent)
    resp2 = client.post("/v1/auth/device", json={"device_id": "device-abc"})
    assert resp2.json()["user_id"] == body["user_id"]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && uv run pytest tests/test_auth.py::test_device_auth_provisions_user_and_returns_token -v`
Expected: FAIL with 404 (route not registered).

- [ ] **Step 3: Create `backend/app/schemas/__init__.py` (auth slice)**

```python
from pydantic import BaseModel


class DeviceAuthRequest(BaseModel):
    device_id: str


class DeviceAuthResponse(BaseModel):
    token: str
    user_id: str
```

- [ ] **Step 4: Create `backend/app/routers/auth.py`**

```python
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import create_token
from app.db import get_db
from app.models import Device, User
from app.schemas import DeviceAuthRequest, DeviceAuthResponse

router = APIRouter(prefix="/v1/auth", tags=["auth"])


@router.post("/device", response_model=DeviceAuthResponse)
def device_auth(body: DeviceAuthRequest, db: Session = Depends(get_db)) -> DeviceAuthResponse:
    device = db.scalar(select(Device).where(Device.device_id == body.device_id))
    if device is None:
        now = datetime.now(timezone.utc)
        user = User(id=str(uuid.uuid4()), auth_provider="device", created_at=now, updated_at=now)
        db.add(user)
        device = Device(id=str(uuid.uuid4()), device_id=body.device_id, user_id=user.id, created_at=now)
        db.add(device)
        db.commit()
    return DeviceAuthResponse(token=create_token(device.user_id), user_id=device.user_id)
```

- [ ] **Step 5: Register the router in `backend/app/main.py`**

```python
from fastapi import FastAPI

from app.routers import auth

app = FastAPI(title="Interactive Storybook API", version="0.1.0")
app.include_router(auth.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd backend && uv run pytest tests/test_auth.py -v`
Expected: PASS (3 passed).

- [ ] **Step 7: Commit**

```bash
git add backend/app/schemas/__init__.py backend/app/routers/__init__.py backend/app/routers/auth.py backend/app/main.py backend/tests/test_auth.py
git commit -m "feat(backend): POST /v1/auth/device provisions user + JWT"
```

---

## PHASE C — Backend content, profiles, sessions

### Task 8: Pydantic response/request schemas

**Files:**
- Modify: `backend/app/schemas/__init__.py`

- [ ] **Step 1: Append content/profile/session schemas to `backend/app/schemas/__init__.py`**

```python
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict


class _ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class StoryOut(_ORM):
    id: str
    title: str
    slug: str
    description: str | None = None
    age_min: int
    age_max: int
    language_code: str
    duration_seconds: int
    cover_asset_id: str | None = None
    content_status: str
    rights_owner_id: str | None = None
    themes: list[str] = []
    is_downloaded: bool = False
    is_unlocked: bool = True


class LibraryResponse(BaseModel):
    stories: list[StoryOut]


class PageOut(_ORM):
    id: str
    story_id: str
    page_number: int
    page_text: str | None = None
    page_image_asset_id: str | None = None
    image_target_id: str | None = None


class SegmentOut(_ORM):
    id: str
    story_id: str
    page_id: str
    speaker_key: str
    text: str
    voice_id: str
    emotion: str | None = None
    speed: float | None = None
    audio_asset_id: str | None = None
    start_ms: int | None = None
    end_ms: int | None = None
    sort_order: int


class ArSceneOut(_ORM):
    id: str
    story_id: str
    page_id: str
    status: str
    scene_json: dict[str, Any]


class ChoiceOut(_ORM):
    id: str
    label: str
    emoji: str | None = None
    is_correct: bool


class QuestionOut(_ORM):
    id: str
    page_id: str
    type: str
    prompt: str
    choices: list[ChoiceOut]


class StoryDetailResponse(BaseModel):
    story: StoryOut
    pages: list[PageOut]
    segments: list[SegmentOut]
    ar_scenes: list[ArSceneOut]
    questions: list[QuestionOut]


class ChildProfileIn(BaseModel):
    id: str
    nickname: str | None = None
    age_band: str
    language_code: str = "en"
    bedtime_mode_default: bool = False
    microphone_enabled: bool = False
    ar_enabled: bool = True


class ChildProfileOut(_ORM):
    id: str
    user_id: str
    nickname: str | None = None
    age_band: str
    language_code: str
    bedtime_mode_default: bool
    microphone_enabled: bool
    ar_enabled: bool


class StartSessionRequest(BaseModel):
    child_profile_id: str
    story_id: str
    mode: str = "library"


class PatchSessionRequest(BaseModel):
    last_page_number: int | None = None
    completed: bool | None = None


class SessionOut(_ORM):
    id: str
    child_profile_id: str
    story_id: str
    started_at: datetime
    completed_at: datetime | None = None
    last_page_number: int
    mode: str


class EventRequest(BaseModel):
    event_type: str
    page_id: str | None = None
    payload: dict[str, Any] = {}


class EventOut(_ORM):
    id: str
    story_session_id: str
    event_type: str
    page_id: str | None = None
    payload: dict[str, Any]
    created_at: datetime
```

- [ ] **Step 2: Verify schemas import**

Run: `cd backend && uv run python -c "from app.schemas import StoryDetailResponse, SessionOut, ChildProfileOut; print('ok')"`
Expected: prints `ok`

- [ ] **Step 3: Commit**

```bash
git add backend/app/schemas/__init__.py
git commit -m "feat(backend): pydantic schemas mirroring client DTOs"
```

---

### Task 9: Stories router + contract test

**Files:**
- Create: `backend/app/repositories/__init__.py` (empty)
- Create: `backend/app/repositories/stories.py`
- Create: `backend/app/routers/stories.py`
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_stories.py`, `backend/tests/test_contract.py`

- [ ] **Step 1: Add a `seeded` fixture to `backend/tests/conftest.py`**

Append:
```python
import pytest
from pathlib import Path
from seed import seed_all


@pytest.fixture
def seeded(db):
    data_dir = Path(__file__).resolve().parent.parent.parent / "assets" / "data"
    seed_all(db, data_dir)
    return db
```
Note: `seed_all` commits; inside the test transaction that commit is contained by the outer connection transaction and rolled back after the test.

- [ ] **Step 2: Write failing tests `backend/tests/test_stories.py`**

```python
def _auth(client):
    token = client.post("/v1/auth/device", json={"device_id": "d1"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def test_library_lists_published_stories(client, seeded):
    resp = client.get("/v1/stories", headers=_auth(client))
    assert resp.status_code == 200
    stories = resp.json()["stories"]
    assert len(stories) == 5
    assert all(s["is_unlocked"] for s in stories)


def test_library_filters_by_age_band(client, seeded):
    resp = client.get("/v1/stories?age_band=3-4", headers=_auth(client))
    titles = [s["title"] for s in resp.json()["stories"]]
    assert "Bunny and the Moon" in titles  # age_min 3, age_max 5


def test_story_detail_404_for_unknown(client, seeded):
    resp = client.get("/v1/stories/nope", headers=_auth(client))
    assert resp.status_code == 404


def test_requires_auth(client, seeded):
    assert client.get("/v1/stories").status_code == 401
```

- [ ] **Step 3: Run to verify failure**

Run: `cd backend && uv run pytest tests/test_stories.py -v`
Expected: FAIL with 404/route-missing.

- [ ] **Step 4: Create `backend/app/repositories/stories.py`**

```python
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import ArScene, NarrationSegment, Question, Story, StoryPage

# Age bands -> (min, max) per enums.dart
_BANDS = {"3-4": (3, 4), "5-6": (5, 6), "7-8": (7, 8)}


def list_published(db: Session, age_band: str | None, language: str | None) -> list[Story]:
    stmt = select(Story).where(Story.content_status == "published")
    if language:
        stmt = stmt.where(Story.language_code == language)
    stories = list(db.scalars(stmt))
    if age_band and age_band in _BANDS:
        lo, hi = _BANDS[age_band]
        stories = [s for s in stories if s.age_min <= hi and s.age_max >= lo]
    return stories


def get_detail(db: Session, story_id: str) -> dict | None:
    story = db.get(Story, story_id)
    if story is None:
        return None
    pages = list(db.scalars(select(StoryPage).where(StoryPage.story_id == story_id)
                            .order_by(StoryPage.page_number)))
    segments = list(db.scalars(select(NarrationSegment).where(NarrationSegment.story_id == story_id)
                               .order_by(NarrationSegment.sort_order)))
    ar_scenes = list(db.scalars(select(ArScene).where(ArScene.story_id == story_id)))
    questions = list(db.scalars(select(Question).where(Question.story_id == story_id)
                                .order_by(Question.sort_order)))
    return {"story": story, "pages": pages, "segments": segments,
            "ar_scenes": ar_scenes, "questions": questions}
```

- [ ] **Step 5: Create `backend/app/routers/stories.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import stories as repo
from app.schemas import LibraryResponse, StoryDetailResponse

router = APIRouter(prefix="/v1/stories", tags=["stories"])


@router.get("", response_model=LibraryResponse)
def library(
    age_band: str | None = None,
    language: str | None = None,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> LibraryResponse:
    return LibraryResponse(stories=repo.list_published(db, age_band, language))


@router.get("/{story_id}", response_model=StoryDetailResponse)
def detail(
    story_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> StoryDetailResponse:
    payload = repo.get_detail(db, story_id)
    if payload is None:
        raise HTTPException(status_code=404, detail="story not found")
    return payload
```

- [ ] **Step 6: Register the router in `backend/app/main.py`**

Add `from app.routers import auth, stories` and `app.include_router(stories.router)`.

- [ ] **Step 7: Run to verify pass**

Run: `cd backend && uv run pytest tests/test_stories.py -v`
Expected: PASS (4 passed).

- [ ] **Step 8: Write the contract test `backend/tests/test_contract.py`**

```python
import json
from pathlib import Path

import pytest

DATA_DIR = Path(__file__).resolve().parent.parent.parent / "assets" / "data"
SLUGS = json.loads((DATA_DIR / "manifest.json").read_text())["stories"]


def _auth(client):
    token = client.post("/v1/auth/device", json={"device_id": "dc"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def _strip_runtime(story: dict) -> dict:
    # Server-derived flags the bundled file may set differently.
    return {k: v for k, v in story.items() if k not in ("is_downloaded", "is_unlocked")}


@pytest.mark.parametrize("slug", SLUGS)
def test_detail_reproduces_bundled_json(client, seeded, slug):
    bundled = json.loads((DATA_DIR / f"{slug}.json").read_text())
    story_id = bundled["story"]["id"]
    got = client.get(f"/v1/stories/{story_id}", headers=_auth(client)).json()

    assert _strip_runtime(got["story"]) == _strip_runtime(bundled["story"])
    assert {p["id"] for p in got["pages"]} == {p["id"] for p in bundled["pages"]}
    assert {s["id"] for s in got["segments"]} == {s["id"] for s in bundled["segments"]}
    assert len(got["questions"]) == len(bundled["questions"])
    for q_got, q_exp in zip(got["questions"], bundled["questions"]):
        assert q_got["prompt"] == q_exp["prompt"]
        assert [c["id"] for c in q_got["choices"]] == [c["id"] for c in q_exp["choices"]]
    # AR scene_json preserved verbatim where present
    assert {a["id"] for a in got["ar_scenes"]} == {a["id"] for a in bundled.get("ar_scenes", [])}
```

- [ ] **Step 9: Run the contract test**

Run: `cd backend && uv run pytest tests/test_contract.py -v`
Expected: PASS (5 passed — one per story).

- [ ] **Step 10: Commit**

```bash
git add backend/app/repositories backend/app/routers/stories.py backend/app/main.py backend/tests/conftest.py backend/tests/test_stories.py backend/tests/test_contract.py
git commit -m "feat(backend): GET /v1/stories + detail with contract test"
```

---

### Task 10: Child-profiles router

**Files:**
- Create: `backend/app/repositories/profiles.py`
- Create: `backend/app/routers/profiles.py`
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_profiles.py`

- [ ] **Step 1: Write failing tests `backend/tests/test_profiles.py`**

```python
import uuid


def _auth(client, device="p-dev"):
    token = client.post("/v1/auth/device", json={"device_id": device}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def _profile_body():
    return {"id": str(uuid.uuid4()), "nickname": "Bun", "age_band": "3-4",
            "language_code": "en", "bedtime_mode_default": False,
            "microphone_enabled": False, "ar_enabled": True}


def test_create_and_list_profile(client):
    h = _auth(client)
    body = _profile_body()
    created = client.post("/v1/child-profiles", json=body, headers=h)
    assert created.status_code == 200
    assert created.json()["user_id"]  # set from JWT, not body

    listed = client.get("/v1/child-profiles", headers=h).json()
    assert [p["id"] for p in listed] == [body["id"]]


def test_patch_updates_permissions(client):
    h = _auth(client)
    body = _profile_body()
    client.post("/v1/child-profiles", json=body, headers=h)
    patched = client.patch(f"/v1/child-profiles/{body['id']}",
                           json={"microphone_enabled": True}, headers=h)
    assert patched.json()["microphone_enabled"] is True


def test_profiles_isolated_per_device(client):
    body = _profile_body()
    client.post("/v1/child-profiles", json=body, headers=_auth(client, "dev-A"))
    other = client.get("/v1/child-profiles", headers=_auth(client, "dev-B")).json()
    assert other == []
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && uv run pytest tests/test_profiles.py -v`
Expected: FAIL (routes missing).

- [ ] **Step 3: Create `backend/app/repositories/profiles.py`**

```python
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import ChildProfile


def list_for_user(db: Session, user_id: str) -> list[ChildProfile]:
    return list(db.scalars(select(ChildProfile).where(ChildProfile.user_id == user_id)))


def upsert(db: Session, user_id: str, data: dict) -> ChildProfile:
    now = datetime.now(timezone.utc)
    existing = db.get(ChildProfile, data["id"])
    if existing is not None and existing.user_id != user_id:
        existing = None  # treat as not-yours -> caller 404s
    if existing is None:
        profile = ChildProfile(id=data["id"], user_id=user_id, created_at=now, updated_at=now,
                               **{k: v for k, v in data.items() if k != "id"})
        db.add(profile)
    else:
        for k, v in data.items():
            if k != "id":
                setattr(existing, k, v)
        existing.updated_at = now
        profile = existing
    db.commit()
    return profile


def get_owned(db: Session, user_id: str, profile_id: str) -> ChildProfile | None:
    p = db.get(ChildProfile, profile_id)
    return p if p is not None and p.user_id == user_id else None
```

- [ ] **Step 4: Create `backend/app/routers/profiles.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import profiles as repo
from app.schemas import ChildProfileIn, ChildProfileOut

router = APIRouter(prefix="/v1/child-profiles", tags=["child-profiles"])


@router.get("", response_model=list[ChildProfileOut])
def list_profiles(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return repo.list_for_user(db, user.id)


@router.post("", response_model=ChildProfileOut)
def create_profile(body: ChildProfileIn, db: Session = Depends(get_db),
                   user: User = Depends(get_current_user)):
    return repo.upsert(db, user.id, body.model_dump())


@router.patch("/{profile_id}", response_model=ChildProfileOut)
def patch_profile(profile_id: str, body: dict, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    existing = repo.get_owned(db, user.id, profile_id)
    if existing is None:
        raise HTTPException(status_code=404, detail="profile not found")
    merged = {
        "id": profile_id,
        "nickname": body.get("nickname", existing.nickname),
        "age_band": body.get("age_band", existing.age_band),
        "language_code": body.get("language_code", existing.language_code),
        "bedtime_mode_default": body.get("bedtime_mode_default", existing.bedtime_mode_default),
        "microphone_enabled": body.get("microphone_enabled", existing.microphone_enabled),
        "ar_enabled": body.get("ar_enabled", existing.ar_enabled),
    }
    return repo.upsert(db, user.id, merged)
```

- [ ] **Step 5: Register router** in `backend/app/main.py` (`from app.routers import auth, stories, profiles`; `app.include_router(profiles.router)`).

- [ ] **Step 6: Run to verify pass**

Run: `cd backend && uv run pytest tests/test_profiles.py -v`
Expected: PASS (3 passed).

- [ ] **Step 7: Commit**

```bash
git add backend/app/repositories/profiles.py backend/app/routers/profiles.py backend/app/main.py backend/tests/test_profiles.py
git commit -m "feat(backend): child-profiles CRUD scoped to device user"
```

---

### Task 11: Story-sessions router (+ events, + reads, + event parity)

**Files:**
- Create: `backend/app/repositories/sessions.py`
- Create: `backend/app/routers/sessions.py`
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_sessions.py`

- [ ] **Step 1: Write failing tests `backend/tests/test_sessions.py`**

```python
import uuid


def _auth(client, device="s-dev"):
    return {"Authorization": f"Bearer {client.post('/v1/auth/device', json={'device_id': device}).json()['token']}"}


def _make_profile(client, h):
    pid = str(uuid.uuid4())
    client.post("/v1/child-profiles",
                json={"id": pid, "age_band": "3-4", "language_code": "en"}, headers=h)
    return pid


def test_start_session_emits_story_started(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    resp = client.post("/v1/story-sessions",
                       json={"child_profile_id": pid, "story_id": "story_bunny_forest", "mode": "bedtime"},
                       headers=h)
    assert resp.status_code == 200
    sid = resp.json()["id"]
    events = client.get(f"/v1/story-sessions/{sid}/events", headers=h).json()
    assert any(e["event_type"] == "story_started" for e in events)


def test_patch_complete_emits_story_completed(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    sid = client.post("/v1/story-sessions",
                      json={"child_profile_id": pid, "story_id": "story_bunny_forest"},
                      headers=h).json()["id"]
    patched = client.patch(f"/v1/story-sessions/{sid}",
                          json={"last_page_number": 5, "completed": True}, headers=h).json()
    assert patched["last_page_number"] == 5
    assert patched["completed_at"] is not None
    events = client.get(f"/v1/story-sessions/{sid}/events", headers=h).json()
    assert any(e["event_type"] == "story_completed" for e in events)


def test_record_question_answered_event(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    sid = client.post("/v1/story-sessions",
                      json={"child_profile_id": pid, "story_id": "story_bunny_forest"},
                      headers=h).json()["id"]
    resp = client.post(f"/v1/story-sessions/{sid}/events",
                      json={"event_type": "question_answered", "page_id": "page_bunny_03",
                            "payload": {"question_id": "q_bunny_02", "answer_id": "a_owl", "is_correct": True}},
                      headers=h)
    assert resp.status_code == 200


def test_list_sessions_by_child(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    client.post("/v1/story-sessions",
                json={"child_profile_id": pid, "story_id": "story_bunny_forest"}, headers=h)
    listed = client.get(f"/v1/story-sessions?child_profile_id={pid}", headers=h).json()
    assert len(listed) == 1
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && uv run pytest tests/test_sessions.py -v`
Expected: FAIL (routes missing).

- [ ] **Step 3: Create `backend/app/repositories/sessions.py`**

```python
import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import ChildProfile, InteractionEvent, StorySession


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _owns_profile(db: Session, user_id: str, child_profile_id: str) -> bool:
    p = db.get(ChildProfile, child_profile_id)
    return p is not None and p.user_id == user_id


def record_event(db: Session, session_id: str, event_type: str,
                 page_id: str | None = None, payload: dict | None = None) -> InteractionEvent:
    event = InteractionEvent(id=str(uuid.uuid4()), story_session_id=session_id,
                             event_type=event_type, page_id=page_id,
                             payload=payload or {}, created_at=_now())
    db.add(event)
    db.commit()
    return event


def start(db: Session, story_id: str, child_profile_id: str, mode: str) -> StorySession:
    s = StorySession(id=str(uuid.uuid4()), child_profile_id=child_profile_id,
                     story_id=story_id, started_at=_now(), mode=mode)
    db.add(s)
    db.commit()
    record_event(db, s.id, "story_started", payload={"story_id": story_id, "mode": mode})
    return s


def get_owned(db: Session, user_id: str, session_id: str) -> StorySession | None:
    s = db.get(StorySession, session_id)
    if s is None or not _owns_profile(db, user_id, s.child_profile_id):
        return None
    return s


def patch(db: Session, s: StorySession, last_page_number: int | None, completed: bool | None) -> StorySession:
    if last_page_number is not None:
        s.last_page_number = last_page_number
    newly_completed = bool(completed) and s.completed_at is None
    if newly_completed:
        s.completed_at = _now()
    db.commit()
    if newly_completed:
        record_event(db, s.id, "story_completed")
    return s


def list_for_child(db: Session, user_id: str, child_profile_id: str) -> list[StorySession]:
    if not _owns_profile(db, user_id, child_profile_id):
        return []
    return list(db.scalars(select(StorySession).where(StorySession.child_profile_id == child_profile_id)))


def list_events(db: Session, session_id: str) -> list[InteractionEvent]:
    return list(db.scalars(select(InteractionEvent)
                           .where(InteractionEvent.story_session_id == session_id)
                           .order_by(InteractionEvent.created_at)))
```

- [ ] **Step 4: Create `backend/app/routers/sessions.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import sessions as repo
from app.schemas import (
    EventOut,
    EventRequest,
    PatchSessionRequest,
    SessionOut,
    StartSessionRequest,
)

router = APIRouter(prefix="/v1/story-sessions", tags=["story-sessions"])


@router.post("", response_model=SessionOut)
def start_session(body: StartSessionRequest, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    if not repo._owns_profile(db, user.id, body.child_profile_id):
        raise HTTPException(status_code=404, detail="profile not found")
    return repo.start(db, body.story_id, body.child_profile_id, body.mode)


@router.get("", response_model=list[SessionOut])
def list_sessions(child_profile_id: str, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    return repo.list_for_child(db, user.id, child_profile_id)


@router.patch("/{session_id}", response_model=SessionOut)
def patch_session(session_id: str, body: PatchSessionRequest, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    s = repo.get_owned(db, user.id, session_id)
    if s is None:
        raise HTTPException(status_code=404, detail="session not found")
    return repo.patch(db, s, body.last_page_number, body.completed)


@router.post("/{session_id}/events", response_model=EventOut)
def add_event(session_id: str, body: EventRequest, db: Session = Depends(get_db),
             user: User = Depends(get_current_user)):
    s = repo.get_owned(db, user.id, session_id)
    if s is None:
        raise HTTPException(status_code=404, detail="session not found")
    return repo.record_event(db, session_id, body.event_type, body.page_id, body.payload)


@router.get("/{session_id}/events", response_model=list[EventOut])
def get_events(session_id: str, db: Session = Depends(get_db),
              user: User = Depends(get_current_user)):
    s = repo.get_owned(db, user.id, session_id)
    if s is None:
        raise HTTPException(status_code=404, detail="session not found")
    return repo.list_events(db, session_id)
```

- [ ] **Step 5: Register router** in `backend/app/main.py` (`from app.routers import auth, stories, profiles, sessions`; `app.include_router(sessions.router)`).

- [ ] **Step 6: Run to verify pass**

Run: `cd backend && uv run pytest tests/test_sessions.py -v`
Expected: PASS (4 passed).

- [ ] **Step 7: Run the full backend suite**

Run: `cd backend && uv run pytest -v`
Expected: all tests pass (auth, stories, contract, profiles, sessions).

- [ ] **Step 8: Commit**

```bash
git add backend/app/repositories/sessions.py backend/app/routers/sessions.py backend/app/main.py backend/tests/test_sessions.py
git commit -m "feat(backend): story-sessions, events, reads with event parity"
```

---

## PHASE D — Client HTTP swap

### Task 12: Add `dio` + `http_mock_adapter`

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the deps** (runtime `dio`, dev `http_mock_adapter`)

In `pubspec.yaml` under `dependencies:` add `  dio: ^5.7.0` after `camera:`.
Under `dev_dependencies:` add `  http_mock_adapter: ^0.6.1`.

- [ ] **Step 2: Resolve**

Run: `flutter pub get`
Expected: resolves; `dio` and `http_mock_adapter` appear in `pubspec.lock`.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: add dio + http_mock_adapter for HTTP repositories"
```

---

### Task 13: API client + device-auth interceptor

> ### 🔒 SECURITY AMENDMENT (device_secret) — applies to this task
> The `ApiClient` must persist the `device_secret` returned on first registration and
> send it on every subsequent `/v1/auth/device` call. Changes to the `ApiClient` below:
> - Add `static const _secretKey = 'device_secret';`
> - In `_ensureToken`, post `{'device_id': _deviceId(), if (secret != null) 'device_secret': secret}`
>   where `secret = _store.getString(_secretKey)`; if the response JSON contains a non-null
>   `device_secret`, persist it: `await _store.setString(_secretKey, resp.data['device_secret'])`.
> - The 401-retry path stays the same: it clears only the token (NOT the secret) and
>   re-mints via device_id + stored secret. Add a test: a 401 then a successful re-mint
>   that sends the stored `device_secret`.

**Files:**
- Create: `lib/data/sources/api_client.dart`
- Test: `test/http_repositories_test.dart`

- [ ] **Step 1: Write the failing test `test/http_repositories_test.dart` (auth bootstrap)**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:storybook_ar/data/sources/api_client.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ApiClient> _client(DioAdapter Function(Dio) wire) async {
  SharedPreferences.setMockInitialValues({});
  final store = await KeyValueStore.create();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  final adapter = DioAdapter(dio: dio);
  wire(adapter);
  return ApiClient(dio: dio, store: store);
}

void main() {
  test('bootstraps a device token and attaches it as Bearer', () async {
    late ApiClient api;
    api = await _client((adapter) {
      adapter.onPost('/v1/auth/device', (s) => s.reply(200, {'token': 't0k', 'user_id': 'u1'}));
      adapter.onGet('/v1/stories', (s) => s.reply(200, {'stories': []}),
          headers: {'Authorization': 'Bearer t0k'});
    });
    final resp = await api.dio.get('/v1/stories');
    expect(resp.statusCode, 200);
    expect(api.userId, 'u1');
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/http_repositories_test.dart`
Expected: FAIL — `api_client.dart` not found.

- [ ] **Step 3: Create `lib/data/sources/api_client.dart`**

```dart
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'key_value_store.dart';

/// Wraps a [Dio] with anonymous device auth (spec §7): on first use it
/// generates+persists a device id, exchanges it for a JWT, and attaches the
/// JWT as a Bearer header. Re-bootstraps on 401.
class ApiClient {
  ApiClient({required this.dio, required KeyValueStore store, Uuid? uuid})
      : _store = store,
        _uuid = uuid ?? const Uuid() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (!options.path.endsWith('/v1/auth/device')) {
          final token = await _ensureToken();
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        if (e.response?.statusCode == 401) {
          await _store.remove(_tokenKey);
          final token = await _ensureToken();
          final req = e.requestOptions..headers['Authorization'] = 'Bearer $token';
          handler.resolve(await dio.fetch(req));
          return;
        }
        handler.next(e);
      },
    ));
  }

  final Dio dio;
  final KeyValueStore _store;
  final Uuid _uuid;

  static const _deviceKey = 'device_id';
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user_id';

  String? get userId => _store.getString(_userKey);

  String _deviceId() {
    final existing = _store.getString(_deviceKey);
    if (existing != null) return existing;
    final id = _uuid.v4();
    _store.setString(_deviceKey, id);
    return id;
  }

  Future<String> _ensureToken() async {
    final cached = _store.getString(_tokenKey);
    if (cached != null) return cached;
    final resp = await dio.post('/v1/auth/device', data: {'device_id': _deviceId()});
    final token = resp.data['token'] as String;
    await _store.setString(_tokenKey, token);
    await _store.setString(_userKey, resp.data['user_id'] as String);
    return token;
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/http_repositories_test.dart`
Expected: PASS (1 passing).

- [ ] **Step 5: Commit**

```bash
git add lib/data/sources/api_client.dart test/http_repositories_test.dart
git commit -m "feat(client): ApiClient with device-auth interceptor"
```

---

### Task 14: HttpStoryRepository

**Files:**
- Create: `lib/data/repositories/http_story_repository.dart`
- Test: `test/http_repositories_test.dart`

- [ ] **Step 1: Add the failing test to `test/http_repositories_test.dart`**

```dart
// add inside main():
  test('HttpStoryRepository parses library and detail', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    final adapter = DioAdapter(dio: dio);
    adapter.onPost('/v1/auth/device', (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
    adapter.onGet('/v1/stories', (s) => s.reply(200, {
          'stories': [
            {'id': 'story_bunny_forest', 'title': 'Bunny and the Moon', 'slug': 'bunny_and_the_moon',
             'age_min': 3, 'age_max': 5, 'language_code': 'en', 'duration_seconds': 300,
             'content_status': 'published', 'themes': ['animals', 'bedtime'],
             'is_downloaded': false, 'is_unlocked': true}
          ]
        }));
    final api = ApiClient(dio: dio, store: store);
    final repo = HttpStoryRepository(api);
    final lib = await repo.getLibrary();
    expect(lib.single.id, 'story_bunny_forest');
    expect(lib.single.title, 'Bunny and the Moon');
  });
```
Add import: `import 'package:storybook_ar/data/repositories/http_story_repository.dart';` and `import 'package:storybook_ar/data/models/models.dart';`

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/http_repositories_test.dart`
Expected: FAIL — `HttpStoryRepository` not found.

- [ ] **Step 3: Create `lib/data/repositories/http_story_repository.dart`**

```dart
import '../models/models.dart';
import '../sources/api_client.dart';
import 'story_repository.dart';

/// HTTP implementation of [StoryRepository] backed by GET /v1/stories
/// (spec §11.1) and GET /v1/stories/{id} (§11.2).
class HttpStoryRepository implements StoryRepository {
  HttpStoryRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Story>> getLibrary({AgeBand? ageBand, String? language}) async {
    final resp = await _api.dio.get('/v1/stories', queryParameters: {
      if (ageBand != null) 'age_band': ageBand.label,
      if (language != null) 'language': language,
    });
    final list = (resp.data['stories'] as List).cast<Map<String, dynamic>>();
    return list.map(Story.fromJson).toList();
  }

  @override
  Future<StoryDetail?> getStory(String storyId) async {
    try {
      final resp = await _api.dio.get('/v1/stories/$storyId');
      return StoryDetail.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
```
Add `import 'package:dio/dio.dart';` at the top.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/http_repositories_test.dart`
Expected: PASS (2 passing).

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/http_story_repository.dart test/http_repositories_test.dart
git commit -m "feat(client): HttpStoryRepository"
```

---

### Task 15: HttpProfileRepository

**Files:**
- Create: `lib/data/repositories/http_profile_repository.dart`
- Test: `test/http_repositories_test.dart`

- [ ] **Step 1: Add the failing test**

```dart
  test('HttpProfileRepository saves and reads back a profile', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    final adapter = DioAdapter(dio: dio);
    adapter.onPost('/v1/auth/device', (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
    const pjson = {'id': 'p1', 'user_id': 'u', 'nickname': 'Bun', 'age_band': '3-4',
        'language_code': 'en', 'bedtime_mode_default': false,
        'microphone_enabled': false, 'ar_enabled': true};
    adapter.onPost('/v1/child-profiles', (s) => s.reply(200, pjson));
    adapter.onGet('/v1/child-profiles', (s) => s.reply(200, [pjson]));
    final repo = HttpProfileRepository(ApiClient(dio: dio, store: store), store);
    await repo.saveProfile(const ChildProfile(id: 'p1', nickname: 'Bun', ageBand: AgeBand.threeToFour));
    final got = await repo.getProfile();
    expect(got!.nickname, 'Bun');
    expect(got.ageBand, AgeBand.threeToFour);
  });
```
Add import: `import 'package:storybook_ar/data/repositories/http_profile_repository.dart';`

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/http_repositories_test.dart`
Expected: FAIL — `HttpProfileRepository` not found.

- [ ] **Step 3: Create `lib/data/repositories/http_profile_repository.dart`**

```dart
import '../models/models.dart';
import '../sources/api_client.dart';
import '../sources/key_value_store.dart';
import 'profile_repository.dart';

/// HTTP implementation of [ProfileRepository]. Child profiles live server-side
/// (scoped to the device user); consent stays a local flag (§14.2).
class HttpProfileRepository implements ProfileRepository {
  HttpProfileRepository(this._api, this._store);

  final ApiClient _api;
  final KeyValueStore _store;

  static const _consentKey = 'parent_consent';

  @override
  Future<ChildProfile?> getProfile() async {
    final resp = await _api.dio.get('/v1/child-profiles');
    final list = (resp.data as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    return ChildProfile.fromJson(list.first);
  }

  @override
  Future<void> saveProfile(ChildProfile profile) async {
    final body = profile.toJson()..remove('user_id'); // server sets user_id from JWT
    await _api.dio.post('/v1/child-profiles', data: body);
  }

  @override
  bool get hasConsented => _store.getBool(_consentKey);

  @override
  Future<void> setConsented(bool value) => _store.setBool(_consentKey, value);

  @override
  bool get isOnboarded => hasConsented && _store.getString('auth_user_id') != null;
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/http_repositories_test.dart`
Expected: PASS (3 passing).

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/http_profile_repository.dart test/http_repositories_test.dart
git commit -m "feat(client): HttpProfileRepository"
```

---

### Task 16: HttpSessionRepository

**Files:**
- Create: `lib/data/repositories/http_session_repository.dart`
- Test: `test/http_repositories_test.dart`

- [ ] **Step 1: Add the failing test**

```dart
  test('HttpSessionRepository starts a session and parses it', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    final adapter = DioAdapter(dio: dio);
    adapter.onPost('/v1/auth/device', (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
    adapter.onPost('/v1/story-sessions', (s) => s.reply(200, {
          'id': 'sess1', 'child_profile_id': 'p1', 'story_id': 'story_bunny_forest',
          'started_at': '2026-06-18T10:00:00Z', 'completed_at': null,
          'last_page_number': 0, 'mode': 'bedtime'}));
    final repo = HttpSessionRepository(ApiClient(dio: dio, store: store));
    final session = await repo.startSession(
        childProfileId: 'p1', storyId: 'story_bunny_forest', mode: SessionMode.bedtime);
    expect(session.id, 'sess1');
    expect(session.mode, SessionMode.bedtime);
  });
```
Add import: `import 'package:storybook_ar/data/repositories/http_session_repository.dart';`

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/http_repositories_test.dart`
Expected: FAIL — `HttpSessionRepository` not found.

- [ ] **Step 3: Create `lib/data/repositories/http_session_repository.dart`**

```dart
import '../models/models.dart';
import '../sources/api_client.dart';
import 'session_repository.dart';

/// HTTP implementation of [SessionRepository] backed by /v1/story-sessions
/// (spec §11.3/§11.4 + derived PATCH/GET endpoints).
class HttpSessionRepository implements SessionRepository {
  HttpSessionRepository(this._api);

  final ApiClient _api;

  @override
  Future<StorySession> startSession({
    required String childProfileId,
    required String storyId,
    required SessionMode mode,
  }) async {
    final resp = await _api.dio.post('/v1/story-sessions', data: {
      'child_profile_id': childProfileId,
      'story_id': storyId,
      'mode': mode.name,
    });
    return StorySession.fromJson(resp.data as Map<String, dynamic>);
  }

  @override
  Future<void> recordEvent({
    required String sessionId,
    required String eventType,
    String? pageId,
    Map<String, dynamic> payload = const {},
  }) async {
    await _api.dio.post('/v1/story-sessions/$sessionId/events', data: {
      'event_type': eventType,
      'page_id': pageId,
      'payload': payload,
    });
  }

  @override
  Future<void> updateLastPage(String sessionId, int pageNumber) async {
    await _api.dio.patch('/v1/story-sessions/$sessionId',
        data: {'last_page_number': pageNumber});
  }

  @override
  Future<void> completeSession(String sessionId) async {
    await _api.dio.patch('/v1/story-sessions/$sessionId', data: {'completed': true});
  }

  @override
  Future<List<StorySession>> getSessions({String? childProfileId}) async {
    final resp = await _api.dio.get('/v1/story-sessions',
        queryParameters: {if (childProfileId != null) 'child_profile_id': childProfileId});
    return (resp.data as List)
        .cast<Map<String, dynamic>>()
        .map(StorySession.fromJson)
        .toList();
  }

  @override
  Future<List<InteractionEvent>> getEvents({String? sessionId}) async {
    if (sessionId == null) return [];
    final resp = await _api.dio.get('/v1/story-sessions/$sessionId/events');
    return (resp.data as List)
        .cast<Map<String, dynamic>>()
        .map(InteractionEvent.fromJson)
        .toList();
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/http_repositories_test.dart`
Expected: PASS (4 passing).

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/http_session_repository.dart test/http_repositories_test.dart
git commit -m "feat(client): HttpSessionRepository"
```

---

### Task 17: Wire Http* repos into DI behind a base-URL config

**Files:**
- Modify: `lib/core/di.dart`
- Test: full client suite + analyze

- [ ] **Step 1: Replace `lib/core/di.dart` with backend-backed wiring**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/http_profile_repository.dart';
import '../data/repositories/http_session_repository.dart';
import '../data/repositories/http_story_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/story_repository.dart';
import '../data/sources/api_client.dart';
import '../data/sources/key_value_store.dart';

/// Backend base URL. Override at build/run time:
/// `--dart-define=API_BASE_URL=http://10.0.2.2:8000` (Android emulator) etc.
const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Provides the [KeyValueStore]. Overridden in `main()` with the instance built
/// from an initialized [SharedPreferences] so the rest of the graph stays sync.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw UnimplementedError(
    'keyValueStoreProvider must be overridden in main() with a built instance.',
  ),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    dio: Dio(BaseOptions(baseUrl: _apiBaseUrl)),
    store: ref.watch(keyValueStoreProvider),
  ),
);

final storyRepositoryProvider = Provider<StoryRepository>(
  (ref) => HttpStoryRepository(ref.watch(apiClientProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => HttpProfileRepository(
    ref.watch(apiClientProvider),
    ref.watch(keyValueStoreProvider),
  ),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => HttpSessionRepository(ref.watch(apiClientProvider)),
);

// Settings stay local — voice speed / volumes are app-local prefs, not in §10.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => LocalSettingsRepository(ref.watch(keyValueStoreProvider)),
);
```
Note: `localContentSourceProvider` is removed; if any other file imports it, leave a re-export or update those imports. (`grep -rn localContentSourceProvider lib/` to confirm — only `di.dart` and `story_repository` wiring used it.)

- [ ] **Step 2: Static analysis**

Run: `flutter analyze 2>&1 | grep "error •" || echo "no errors"`
Expected: `no errors`. Fix any unused-import errors flagged.

- [ ] **Step 3: Run the full client test suite**

Run: `flutter test`
Expected: all pass — `widget_test.dart`, `content_parsing_test.dart`, `http_repositories_test.dart`.

- [ ] **Step 4: Commit**

```bash
git add lib/core/di.dart
git commit -m "feat(client): wire Http* repositories via API_BASE_URL"
```

---

## Final verification (manual, optional — not part of the automated gate)

- [ ] **Backend up:** `cd backend && docker compose up -d db && uv run alembic upgrade head && uv run python seed.py && uv run uvicorn app.main:app --reload`
- [ ] **App against backend** (only on explicit request, per project rules):
  `flutter run --dart-define=API_BASE_URL=http://localhost:8000` (use `http://10.0.2.2:8000` on Android emulator).
- [ ] Browse library, open a story, play narration, create a profile, complete a story → confirm sessions/events appear via `GET /v1/story-sessions?child_profile_id=…`.

---

## Self-review (completed during planning)

- **Spec coverage:** every §6 endpoint has a task (auth→T7, stories→T9, profiles→T10, sessions/events/reads→T11); client swap §9 → T12–T17; seed/contract §4 → T5/T9; auth model §7 → T6/T7/T13; deferred items remain deferred.
- **Placeholder scan:** no TBD/TODO; every code step contains real code; commands have expected output.
- **Type consistency:** `ApiClient(dio:, store:)`, `HttpProfileRepository(api, store)`, `HttpStoryRepository(api)`, `HttpSessionRepository(api)` used identically across tasks; schema field names match the ORM columns and the bundled JSON keys; `child-profiles` user_id always from JWT.
- **Known coupling:** the `seeded`/`db` fixtures assume a reachable `storybook_test` Postgres DB; Task 6 Step 5 notes creating it once.
