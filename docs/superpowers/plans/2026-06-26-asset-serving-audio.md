# Asset Serving (audio) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve real per-segment narration audio over short-lived HMAC-signed URLs, with a drop-in convention so supplied recordings go live with no code change; the player plays a clip when registered and falls back to TTS otherwise.

**Architecture:** Two-tier signed-URL model inside the existing FastAPI app — an authenticated `POST /v1/assets/sign` returns expiring URLs only for registered assets; a public, signature-validated `GET /v1/assets/{id}` streams the file with HTTP Range support. A new `assets` table maps `asset_id → storage_key`. The client gains an `AssetUrlResolver` that signs the segment asset ids a page needs; `NarrationPlayer` plays the resolved URL or falls back to on-device TTS.

**Tech Stack:** FastAPI · SQLAlchemy 2.0 + Alembic · Starlette `FileResponse` (Range-aware) · `hmac`/`hashlib` · pytest + TestClient · Flutter/Dart · dio + `http_mock_adapter` · just_audio · Riverpod.

**Spec:** `docs/superpowers/specs/2026-06-26-asset-serving-audio-design.md`

**Conventions already in place (do not re-create):** `narration_segments.audio_asset_id` column exists (`app/models/__init__.py:106`); `SegmentOut.audio_asset_id` exists (`app/schemas/__init__.py:61`); `seed.py:47` already ingests `audio_asset_id`; the client `NarrationSegment` model already exposes `audioAssetId` + `hasAudioAsset` (`lib/data/models/narration_segment.dart:31,49`); `ApiClient.send()` handles 401 re-mint (`lib/data/sources/api_client.dart:91`). Current migration head is `7ecd8c44dd25` (`0002_device_secret.py`).

**Run backend tests:** `cd backend && uv run pytest -q` (needs the `storybook_test` DB up, per the project memory).
**Run client tests:** `flutter test test/<file>` from repo root.

---

## Task 1: `assets` table — model + migration

**Files:**
- Modify: `backend/app/models/__init__.py` (add `func` to imports; append `Asset` class)
- Create: `backend/migrations/versions/0003_assets.py`
- Test: `backend/tests/test_assets_model.py`

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_assets_model.py`:

```python
from app.models import Asset


def test_asset_roundtrip(db):
    db.add(Asset(
        asset_id="aud_demo",
        kind="audio",
        storage_key="audio/aud_demo.m4a",
        content_type="audio/mp4",
        byte_size=8,
    ))
    db.flush()
    got = db.get(Asset, "aud_demo")
    assert got is not None
    assert got.kind == "audio"
    assert got.storage_key == "audio/aud_demo.m4a"
    assert got.content_type == "audio/mp4"
    assert got.byte_size == 8
    assert got.duration_ms is None
    assert got.created_at is not None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && uv run pytest tests/test_assets_model.py -q`
Expected: FAIL with `ImportError: cannot import name 'Asset'`.

- [ ] **Step 3: Add the `Asset` model**

In `backend/app/models/__init__.py`, change the SQLAlchemy import line (currently line 3) to add `func`:

```python
from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String, Text, func
```

Append at the end of the file:

```python
class Asset(Base):
    __tablename__ = "assets"
    asset_id: Mapped[str] = mapped_column(String, primary_key=True)
    kind: Mapped[str] = mapped_column(Text)
    storage_key: Mapped[str] = mapped_column(Text)
    content_type: Mapped[str] = mapped_column(Text)
    byte_size: Mapped[int | None] = mapped_column(Integer, nullable=True)
    duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && uv run pytest tests/test_assets_model.py -q`
Expected: PASS (the `conftest` `_schema` fixture creates the table from metadata).

- [ ] **Step 5: Write the Alembic migration**

Create `backend/migrations/versions/0003_assets.py`:

```python
"""assets table

Revision ID: 0a3f7c1d9b22
Revises: 7ecd8c44dd25
Create Date: 2026-06-26 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0a3f7c1d9b22'
down_revision: Union[str, Sequence[str], None] = '7ecd8c44dd25'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'assets',
        sa.Column('asset_id', sa.String(), primary_key=True),
        sa.Column('kind', sa.Text(), nullable=False),
        sa.Column('storage_key', sa.Text(), nullable=False),
        sa.Column('content_type', sa.Text(), nullable=False),
        sa.Column('byte_size', sa.Integer(), nullable=True),
        sa.Column('duration_ms', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table('assets')
```

- [ ] **Step 6: Verify the migration applies cleanly**

Run: `cd backend && uv run alembic upgrade head && uv run alembic downgrade -1 && uv run alembic upgrade head`
Expected: no errors; `assets` table created, dropped, re-created.

- [ ] **Step 7: Commit**

```bash
git add backend/app/models/__init__.py backend/migrations/versions/0003_assets.py backend/tests/test_assets_model.py
git commit -m "feat(backend): add assets table (model + migration 0003)"
```

---

## Task 2: HMAC URL signing utility + config

**Files:**
- Modify: `backend/app/config.py` (add 3 settings)
- Modify: `backend/.env.example` (document the 3 settings)
- Create: `backend/app/assets_signing.py`
- Test: `backend/tests/test_assets_signing.py`

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_assets_signing.py`:

```python
from urllib.parse import urlparse, parse_qs

from app.assets_signing import sign_asset_url, verify_signature


def _parse(url: str) -> tuple[int, str]:
    q = parse_qs(urlparse(url).query)
    return int(q["exp"][0]), q["sig"][0]


def test_sign_then_verify_ok():
    url = sign_asset_url("aud_x", now=1000)
    assert url.startswith("/v1/assets/aud_x?exp=")
    exp, sig = _parse(url)
    assert verify_signature("aud_x", exp, sig, now=1000) is True


def test_verify_rejects_tampered_sig():
    exp, _sig = _parse(sign_asset_url("aud_x", now=1000))
    assert verify_signature("aud_x", exp, "deadbeef", now=1000) is False


def test_verify_rejects_expired():
    exp, sig = _parse(sign_asset_url("aud_x", now=1000))
    assert verify_signature("aud_x", exp, sig, now=10_000_000) is False


def test_verify_rejects_wrong_asset_id():
    exp, sig = _parse(sign_asset_url("aud_x", now=1000))
    assert verify_signature("aud_y", exp, sig, now=1000) is False
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && uv run pytest tests/test_assets_signing.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'app.assets_signing'`.

- [ ] **Step 3: Add config settings**

In `backend/app/config.py`, add inside `Settings` (after `jwt_algorithm`):

```python
    asset_url_secret: str = "dev-asset-secret-0123456789abcdef0123456789abcdef"
    asset_url_ttl_seconds: int = 3600
    storage_dir: str = "storage"
```

In `backend/.env.example`, append:

```
# Asset serving (slice 3). Secret must be >=32 bytes in any real environment.
ASSET_URL_SECRET=dev-asset-secret-0123456789abcdef0123456789abcdef
ASSET_URL_TTL_SECONDS=3600
STORAGE_DIR=storage
```

- [ ] **Step 4: Implement the signing utility**

Create `backend/app/assets_signing.py`:

```python
"""Short-lived HMAC-signed URLs for asset streaming (spec §7.1).

A signed URL is `/v1/assets/{asset_id}?exp=<unix>&sig=<hex>` where
`sig = HMAC_SHA256(ASSET_URL_SECRET, "{asset_id}:{exp}")`. The media request
carries no Bearer token; the signature + expiry are the access proof.
"""
import hashlib
import hmac
import time

from app.config import settings


def _sig(asset_id: str, exp: int) -> str:
    msg = f"{asset_id}:{exp}".encode()
    return hmac.new(settings.asset_url_secret.encode(), msg, hashlib.sha256).hexdigest()


def sign_asset_url(asset_id: str, now: int | None = None) -> str:
    exp = (now if now is not None else int(time.time())) + settings.asset_url_ttl_seconds
    return f"/v1/assets/{asset_id}?exp={exp}&sig={_sig(asset_id, exp)}"


def verify_signature(asset_id: str, exp: int, sig: str, now: int | None = None) -> bool:
    current = now if now is not None else int(time.time())
    if exp <= current:
        return False
    return hmac.compare_digest(sig, _sig(asset_id, exp))
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && uv run pytest tests/test_assets_signing.py -q`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add backend/app/config.py backend/.env.example backend/app/assets_signing.py backend/tests/test_assets_signing.py
git commit -m "feat(backend): HMAC asset-URL signing utility + config"
```

---

## Task 3: Sign + stream endpoints

**Files:**
- Modify: `backend/app/schemas/__init__.py` (add `AssetSignRequest`)
- Create: `backend/app/routers/assets.py`
- Modify: `backend/app/main.py` (register the router)
- Test: `backend/tests/test_assets.py`

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_assets.py`:

```python
import pytest

from app.assets_signing import sign_asset_url
from app.config import settings
from app.models import Asset


def _auth(client):
    token = client.post("/v1/auth/device", json={"device_id": "dc-assets"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def asset_file(db, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "storage_dir", str(tmp_path))
    audio = tmp_path / "audio"
    audio.mkdir()
    (audio / "aud_demo.m4a").write_bytes(b"ABCDEFGH")
    db.add(Asset(asset_id="aud_demo", kind="audio",
                 storage_key="audio/aud_demo.m4a",
                 content_type="audio/mp4", byte_size=8))
    db.flush()
    return "aud_demo"


def test_sign_returns_only_registered(client, asset_file):
    r = client.post("/v1/assets/sign",
                    json={"asset_ids": ["aud_demo", "aud_unknown"]},
                    headers=_auth(client))
    assert r.status_code == 200
    body = r.json()
    assert "aud_demo" in body
    assert "aud_unknown" not in body
    assert body["aud_demo"].startswith("/v1/assets/aud_demo?exp=")


def test_sign_requires_auth(client, asset_file):
    assert client.post("/v1/assets/sign",
                       json={"asset_ids": ["aud_demo"]}).status_code == 401


def test_stream_serves_file(client, asset_file):
    r = client.get(sign_asset_url("aud_demo"))
    assert r.status_code == 200
    assert r.content == b"ABCDEFGH"


def test_stream_supports_range(client, asset_file):
    r = client.get(sign_asset_url("aud_demo"), headers={"Range": "bytes=0-3"})
    assert r.status_code == 206
    assert r.content == b"ABCD"


def test_stream_rejects_bad_sig(client, asset_file):
    assert client.get("/v1/assets/aud_demo?exp=9999999999&sig=deadbeef").status_code == 403


def test_stream_404_unknown_asset(client, asset_file):
    # valid signature, but no asset row
    assert client.get(sign_asset_url("aud_nope")).status_code == 404
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && uv run pytest tests/test_assets.py -q`
Expected: FAIL (404 on `/v1/assets/sign` — router not registered yet).

- [ ] **Step 3: Add the request schema**

In `backend/app/schemas/__init__.py`, append:

```python
class AssetSignRequest(BaseModel):
    asset_ids: list[str]
```

- [ ] **Step 4: Implement the router**

Create `backend/app/routers/assets.py`:

```python
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.assets_signing import sign_asset_url, verify_signature
from app.auth import get_current_user
from app.config import settings
from app.db import get_db
from app.models import Asset, User
from app.schemas import AssetSignRequest

router = APIRouter(prefix="/v1/assets", tags=["assets"])


@router.post("/sign")
def sign(
    req: AssetSignRequest,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> dict[str, str]:
    registered = set(
        db.execute(
            select(Asset.asset_id).where(Asset.asset_id.in_(req.asset_ids))
        ).scalars()
    )
    return {aid: sign_asset_url(aid) for aid in req.asset_ids if aid in registered}


@router.get("/{asset_id}")
def stream(
    asset_id: str,
    exp: int,
    sig: str,
    db: Session = Depends(get_db),
) -> FileResponse:
    if not verify_signature(asset_id, exp, sig):
        raise HTTPException(status_code=403, detail="invalid or expired signature")
    asset = db.get(Asset, asset_id)
    if asset is None:
        raise HTTPException(status_code=404, detail="asset not found")
    path = Path(settings.storage_dir) / asset.storage_key
    if not path.is_file():
        raise HTTPException(status_code=404, detail="file missing")
    return FileResponse(path, media_type=asset.content_type)
```

- [ ] **Step 5: Register the router**

In `backend/app/main.py`, change the import line and add an `include_router` call:

```python
from app.routers import assets, auth, profiles, sessions, stories
```

```python
app.include_router(assets.router)
```

(place the `include_router(assets.router)` next to the other `include_router` calls)

- [ ] **Step 6: Run test to verify it passes**

Run: `cd backend && uv run pytest tests/test_assets.py -q`
Expected: PASS (6 tests).

- [ ] **Step 7: Run the full backend suite (no regressions)**

Run: `cd backend && uv run pytest -q`
Expected: all prior tests still PASS plus the new ones.

- [ ] **Step 8: Commit**

```bash
git add backend/app/schemas/__init__.py backend/app/routers/assets.py backend/app/main.py backend/tests/test_assets.py
git commit -m "feat(backend): /v1/assets sign + Range-aware signed stream endpoints"
```

---

## Task 4: Pre-populate `audio_asset_id` in seed JSON + lock with tests

**Files:**
- Modify: `assets/data/bunny_and_the_moon.json`, `assets/data/lola_learns_to_share.json`, `assets/data/max_and_the_color_garden.json`, `assets/data/sleepy_little_star.json`, `assets/data/the_brave_little_fox.json` (add `audio_asset_id` to every segment)
- Modify: `test/content_parsing_test.dart` (assert the field)
- Modify: `backend/tests/test_contract.py` (assert seed→API wiring)

- [ ] **Step 1: Add the client-side assertion (failing first)**

In `test/content_parsing_test.dart`, inside the `for (final seg in detail.segments)` loop (currently around line 32, after the page-id check), add:

```dart
        expect(seg.audioAssetId, 'aud_${seg.id}',
            reason: 'segment ${seg.id} must carry its pre-populated audio_asset_id');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/content_parsing_test.dart`
Expected: FAIL — `audioAssetId` is null (not yet in the JSON).

- [ ] **Step 3: Apply the deterministic JSON transform**

Run this once from the repo root (additive — sets `audio_asset_id = "aud_<segment_id>"` on every segment; re-serializes with 2-space indent matching the existing format):

```bash
python3 - <<'PY'
import json, pathlib
data_dir = pathlib.Path("assets/data")
slugs = json.loads((data_dir / "manifest.json").read_text())["stories"]
for slug in slugs:
    f = data_dir / f"{slug}.json"
    detail = json.loads(f.read_text())
    for seg in detail.get("segments", []):
        seg["audio_asset_id"] = f"aud_{seg['id']}"
    f.write_text(json.dumps(detail, indent=2, ensure_ascii=False) + "\n")
    print("updated", slug)
PY
```

- [ ] **Step 4: Run the client test to verify it passes**

Run: `flutter test test/content_parsing_test.dart`
Expected: PASS — every segment now reports `aud_<id>`.

- [ ] **Step 5: Add the backend contract assertion**

In `backend/tests/test_contract.py`, inside `test_detail_reproduces_bundled_json`, after the existing segment-id set assertion (line 28), add:

```python
    by_id = {s["id"]: s for s in got["segments"]}
    for s in bundled["segments"]:
        assert by_id[s["id"]]["audio_asset_id"] == f"aud_{s['id']}"
```

- [ ] **Step 6: Run the backend contract test (and full suite) to verify green**

Run: `cd backend && uv run pytest tests/test_contract.py -q && uv run pytest -q`
Expected: PASS — the seed loads `audio_asset_id` (`seed.py:47`) and the API returns it (`SegmentOut.audio_asset_id`); existing id-set comparisons are unaffected.

- [ ] **Step 7: Commit**

```bash
git add assets/data/*.json test/content_parsing_test.dart backend/tests/test_contract.py
git commit -m "feat(content): pre-populate audio_asset_id (aud_<segment_id>) on all segments"
```

---

## Task 5: `register_assets.py` + storage scaffold

**Files:**
- Create: `backend/register_assets.py`
- Create: `backend/storage/audio/.gitkeep`
- Modify: `backend/.gitignore` (ignore dropped media, keep `.gitkeep`) — create the file if absent
- Test: `backend/tests/test_register_assets.py`

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_register_assets.py`:

```python
from app.models import Asset
from register_assets import register


def test_register_creates_row_for_matching_file(seeded, tmp_path):
    audio = tmp_path / "audio"
    audio.mkdir()
    (audio / "aud_seg_bunny_p1_1.m4a").write_bytes(b"xx")
    result = register(seeded, tmp_path)
    assert "aud_seg_bunny_p1_1" in result["registered"]
    assert seeded.get(Asset, "aud_seg_bunny_p1_1") is not None


def test_register_flags_orphan(seeded, tmp_path):
    audio = tmp_path / "audio"
    audio.mkdir()
    (audio / "aud_not_a_segment.m4a").write_bytes(b"xx")
    result = register(seeded, tmp_path)
    assert "aud_not_a_segment.m4a" in result["orphans"]


def test_register_is_idempotent(seeded, tmp_path):
    audio = tmp_path / "audio"
    audio.mkdir()
    (audio / "aud_seg_bunny_p1_1.m4a").write_bytes(b"xx")
    register(seeded, tmp_path)
    register(seeded, tmp_path)
    assert seeded.get(Asset, "aud_seg_bunny_p1_1") is not None
```

(`seg_bunny_p1_1` exists in the seed; Task 4 set its `audio_asset_id` to `aud_seg_bunny_p1_1`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && uv run pytest tests/test_register_assets.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'register_assets'`.

- [ ] **Step 3: Implement the registration script**

Create `backend/register_assets.py`:

```python
"""Register dropped audio recordings into the assets table (spec §8).

Scans <storage_dir>/audio for `<audio_asset_id>.m4a` files. For each file whose
stem matches a seeded narration_segments.audio_asset_id, upserts an `assets`
row. Reports orphan files (no matching segment) and segments still missing
audio. Idempotent (uses merge). Does not delete anything.
"""
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.db import SessionLocal
from app.models import Asset, NarrationSegment

AUDIO_SUBDIR = "audio"
CONTENT_TYPE = "audio/mp4"


def register(db: Session, storage_dir: Path) -> dict:
    known = set(
        db.execute(
            select(NarrationSegment.audio_asset_id)
            .where(NarrationSegment.audio_asset_id.is_not(None))
        ).scalars()
    )
    audio_dir = Path(storage_dir) / AUDIO_SUBDIR
    files = sorted(audio_dir.glob("*.m4a")) if audio_dir.exists() else []

    registered: list[str] = []
    orphans: list[str] = []
    for f in files:
        asset_id = f.stem
        if asset_id not in known:
            orphans.append(f.name)
            continue
        db.merge(Asset(
            asset_id=asset_id,
            kind="audio",
            storage_key=f"{AUDIO_SUBDIR}/{f.name}",
            content_type=CONTENT_TYPE,
            byte_size=f.stat().st_size,
            duration_ms=None,
        ))
        registered.append(asset_id)
    db.flush()

    have = set(db.execute(select(Asset.asset_id)).scalars())
    missing = sorted(known - have)
    return {"registered": registered, "orphans": orphans, "missing": missing}


if __name__ == "__main__":
    db = SessionLocal()
    try:
        result = register(db, Path(settings.storage_dir))
        db.commit()
        print(f"registered {len(result['registered'])} asset(s)")
        if result["orphans"]:
            print(f"orphan files (no matching segment): {result['orphans']}")
        if result["missing"]:
            print(f"segments still missing audio: {len(result['missing'])}")
    finally:
        db.close()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && uv run pytest tests/test_register_assets.py -q`
Expected: PASS (3 tests).

- [ ] **Step 5: Scaffold the storage directory**

```bash
mkdir -p backend/storage/audio
touch backend/storage/audio/.gitkeep
```

Create `backend/.gitignore` if it does not exist, otherwise append:

```
# Dropped media recordings — registered by register_assets.py, not committed.
storage/audio/*
!storage/audio/.gitkeep
```

- [ ] **Step 6: Commit**

```bash
git add backend/register_assets.py backend/tests/test_register_assets.py backend/storage/audio/.gitkeep backend/.gitignore
git commit -m "feat(backend): register_assets.py drop-in registration + storage scaffold"
```

---

## Task 6: Client `AssetUrlResolver` + DI

**Files:**
- Create: `lib/data/sources/asset_url_resolver.dart`
- Modify: `lib/core/di.dart` (add `assetUrlResolverProvider`)
- Test: `test/asset_url_resolver_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/asset_url_resolver_test.dart`:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/data/sources/api_client.dart';
import 'package:storybook_ar/data/sources/asset_url_resolver.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';

(Dio, DioAdapter) _mockDio(void Function(DioAdapter) wire) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
  wire(adapter);
  return (dio, adapter);
}

void main() {
  test('resolves registered ids to absolute URLs and omits unregistered', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    final (dio, _) = _mockDio((a) {
      a.onPost('/v1/auth/device', (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
      a.onPost('/v1/assets/sign', (s) => s.reply(200, {
            'aud_a': '/v1/assets/aud_a?exp=9999999999&sig=ab',
          }));
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final resolver = HttpAssetUrlResolver(api);

    final urls = await resolver.resolve(['aud_a', 'aud_missing']);
    expect(urls['aud_a'], 'http://test/v1/assets/aud_a?exp=9999999999&sig=ab');
    expect(urls.containsKey('aud_missing'), isFalse);
  });

  test('caches resolved ids (second call does not re-sign)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    var signCalls = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _PathAdapter((opts) {
      if (opts.path.endsWith('/v1/auth/device')) {
        return ResponseBody.fromString(
          jsonEncode({'token': 't', 'user_id': 'u'}), 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
      }
      signCalls++; // only /v1/assets/sign reaches here
      return ResponseBody.fromString(
        jsonEncode({'aud_a': '/v1/assets/aud_a?exp=9999999999&sig=ab'}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final resolver = HttpAssetUrlResolver(api);

    await resolver.resolve(['aud_a']);
    await resolver.resolve(['aud_a']);
    expect(signCalls, 1);
  });

  test('returns empty map when signing transport errors', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    final (dio, _) = _mockDio((a) {
      a.onPost('/v1/auth/device', (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
      a.onPost('/v1/assets/sign', (s) => s.reply(500, {'detail': 'boom'}));
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final resolver = HttpAssetUrlResolver(api);

    final urls = await resolver.resolve(['aud_a']);
    expect(urls, isEmpty);
  });
}

/// A [HttpClientAdapter] that delegates each fetch to [onFetch] (used to count
/// requests reliably; mirrors the helper in http_repositories_test.dart).
class _PathAdapter implements HttpClientAdapter {
  _PathAdapter(this.onFetch);

  final ResponseBody Function(RequestOptions) onFetch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<dynamic>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async =>
      onFetch(options);

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/asset_url_resolver_test.dart`
Expected: FAIL — `asset_url_resolver.dart` / `HttpAssetUrlResolver` not found.

- [ ] **Step 3: Implement the resolver**

Create `lib/data/sources/asset_url_resolver.dart`:

```dart
import 'package:dio/dio.dart';

import 'api_client.dart';

/// Resolves narration `audio_asset_id`s to playable, short-lived signed URLs
/// via `POST /v1/assets/sign` (spec §7.1, §9). Ids without a registered file
/// are omitted from the result so the player can fall back to TTS.
abstract class AssetUrlResolver {
  Future<Map<String, String>> resolve(List<String> assetIds);
}

class HttpAssetUrlResolver implements AssetUrlResolver {
  HttpAssetUrlResolver(this._api);

  final ApiClient _api;
  final Map<String, _Signed> _cache = {};

  /// Refresh URLs this many seconds before their `exp` to avoid races.
  static const _skewSeconds = 30;

  @override
  Future<Map<String, String>> resolve(List<String> assetIds) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final result = <String, String>{};
    final missing = <String>[];

    for (final id in assetIds.toSet()) {
      final cached = _cache[id];
      if (cached != null && cached.exp - _skewSeconds > now) {
        result[id] = cached.url;
      } else {
        missing.add(id);
      }
    }
    if (missing.isEmpty) return result;

    try {
      final resp = await _api.send(
        () => _api.dio.post('/v1/assets/sign', data: {'asset_ids': missing}),
      );
      final base = _api.dio.options.baseUrl;
      final map = (resp.data as Map).cast<String, dynamic>();
      map.forEach((id, rel) {
        final url = '$base$rel';
        final exp = int.tryParse(Uri.parse(url).queryParameters['exp'] ?? '') ?? now;
        _cache[id] = _Signed(url, exp);
        result[id] = url;
      });
    } on DioException {
      // Leave unresolved ids out → caller falls back to TTS.
    }
    return result;
  }
}

class _Signed {
  _Signed(this.url, this.exp);
  final String url;
  final int exp;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/asset_url_resolver_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Add the DI provider**

In `lib/core/di.dart`, add the import near the other source imports:

```dart
import '../data/sources/asset_url_resolver.dart';
```

and add the provider (after `apiClientProvider`):

```dart
final assetUrlResolverProvider = Provider<AssetUrlResolver>(
  (ref) => HttpAssetUrlResolver(ref.watch(apiClientProvider)),
);
```

- [ ] **Step 6: Verify analyzer is clean**

Run: `flutter analyze 2>&1 | grep 'error •'`
Expected: no output (no errors).

- [ ] **Step 7: Commit**

```bash
git add lib/data/sources/asset_url_resolver.dart lib/core/di.dart test/asset_url_resolver_test.dart
git commit -m "feat(client): AssetUrlResolver (signs audio asset ids) + DI provider"
```

---

## Task 7: Wire `NarrationPlayer` to served URLs

**Files:**
- Modify: `lib/features/player/narration_player.dart` (resolver param, URL map, `computeTtsFallback`, `setUrl` branch)
- Modify: `lib/features/player/story_player_screen.dart:52,62` (inject resolver)
- Modify: `lib/features/ar/ar_story_screen.dart:75` (inject resolver)
- Test: `test/narration_player_test.dart`

- [ ] **Step 1: Write the failing test (pure fallback-decision logic)**

Create `test/narration_player_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/features/player/narration_player.dart';

NarrationSegment _seg(String id, {String? audioAssetId}) => NarrationSegment(
      id: id,
      storyId: 's',
      pageId: 'p',
      speakerKey: 'narrator',
      text: 'hello',
      voiceId: 'v',
      audioAssetId: audioAssetId,
      sortOrder: 1,
    );

void main() {
  test('no fallback when every segment has a resolved URL', () {
    final segs = [_seg('a', audioAssetId: 'aud_a'), _seg('b', audioAssetId: 'aud_b')];
    final urls = {'aud_a': 'http://x/a', 'aud_b': 'http://x/b'};
    expect(NarrationPlayer.computeTtsFallback(segs, urls), isFalse);
  });

  test('fallback when a segment has an asset id but no resolved URL', () {
    final segs = [_seg('a', audioAssetId: 'aud_a'), _seg('b', audioAssetId: 'aud_b')];
    final urls = {'aud_a': 'http://x/a'}; // aud_b unresolved
    expect(NarrationPlayer.computeTtsFallback(segs, urls), isTrue);
  });

  test('fallback when a segment has no asset id at all', () {
    final segs = [_seg('a', audioAssetId: 'aud_a'), _seg('b')];
    final urls = {'aud_a': 'http://x/a'};
    expect(NarrationPlayer.computeTtsFallback(segs, urls), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/narration_player_test.dart`
Expected: FAIL — `computeTtsFallback` not defined.

- [ ] **Step 3: Add resolver + URL resolution to `NarrationPlayer`**

In `lib/features/player/narration_player.dart`:

Add the import (after the existing `import '../../data/models/models.dart';`):

```dart
import '../../data/sources/asset_url_resolver.dart';
```

Change the constructor (currently lines 20-22) to accept a resolver and store it:

```dart
  NarrationPlayer({AudioPlayer? filePlayer, FlutterTts? tts, AssetUrlResolver? resolver})
      : _file = filePlayer ?? AudioPlayer(),
        _tts = tts ?? FlutterTts(),
        _resolver = resolver;

  final AssetUrlResolver? _resolver;

  /// Resolved signed URLs for the current page, keyed by `audio_asset_id`.
  Map<String, String> _urlByAssetId = {};

  /// True when at least one segment cannot be played from a real clip and must
  /// use the DEV-ONLY TTS fallback. Pure so it is unit-testable without audio.
  static bool computeTtsFallback(
    List<NarrationSegment> segments,
    Map<String, String> urls,
  ) =>
      segments.any((s) => !s.hasAudioAsset || !urls.containsKey(s.audioAssetId));
```

Replace the body of `load()` (currently lines 52-66) so it resolves URLs up front and computes the fallback from them:

```dart
  Future<void> load(
    List<NarrationSegment> segments, {
    double speedMultiplier = 1.0,
    String languageCode = 'en',
  }) async {
    await _haltLoop();
    _segments = segments;
    _speedMultiplier = speedMultiplier;
    _languageCode = languageCode;
    _cursor = 0;
    currentSegmentIndex.value = -1;
    isComplete.value = false;

    final ids = segments
        .where((s) => s.hasAudioAsset)
        .map((s) => s.audioAssetId!)
        .toList();
    _urlByAssetId = (_resolver != null && ids.isNotEmpty)
        ? await _resolver!.resolve(ids)
        : <String, String>{};
    usingTtsFallback.value = computeTtsFallback(segments, _urlByAssetId);
  }
```

Replace the file-audio branch of `_playSegment` (currently lines 109-119) to play the resolved URL instead of a bundled asset:

```dart
    final url = seg.hasAudioAsset ? _urlByAssetId[seg.audioAssetId] : null;
    if (url != null) {
      try {
        await _file.setUrl(url);
        await _file.setSpeed(speed);
        final done = _file.processingStateStream
            .firstWhere((s) => s == ProcessingState.completed);
        unawaited(_file.play());
        await Future.any([done, interrupt]);
      } catch (_) {
        // A missing/corrupt clip shouldn't break the story — fall through.
      }
    } else {
```

(the `else { ... TTS ... }` block that follows stays exactly as-is)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/narration_player_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Inject the resolver in the story player screen**

In `lib/features/player/story_player_screen.dart`:

Add the import (with the other `core`/feature imports):

```dart
import '../../core/di.dart';
```

Change the field (line 52) from:

```dart
  final NarrationPlayer _player = NarrationPlayer();
```

to:

```dart
  late final NarrationPlayer _player;
```

In `initState()` (line 62), as the first line after `super.initState();`, construct it with the resolver:

```dart
    _player = NarrationPlayer(resolver: ref.read(assetUrlResolverProvider));
```

- [ ] **Step 6: Inject the resolver in the AR story screen**

In `lib/features/ar/ar_story_screen.dart`:

Add the import:

```dart
import '../../core/di.dart';
```

Change the field (line 75) from:

```dart
  final NarrationPlayer _audio = NarrationPlayer();
```

to:

```dart
  late final NarrationPlayer _audio;
```

In the `_ArViewState` `initState()` (add one calling `super.initState()` if absent), construct it with the resolver:

```dart
    _audio = NarrationPlayer(resolver: ref.read(assetUrlResolverProvider));
```

- [ ] **Step 7: Verify analyzer is clean and player tests pass**

Run: `flutter analyze 2>&1 | grep 'error •'`
Expected: no output (no errors).

Run: `flutter test test/narration_player_test.dart test/asset_url_resolver_test.dart test/content_parsing_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/player/narration_player.dart lib/features/player/story_player_screen.dart lib/features/ar/ar_story_screen.dart test/narration_player_test.dart
git commit -m "feat(client): play served signed-URL narration, truthful TTS fallback"
```

---

## Final verification (after all tasks)

- [ ] **Backend suite green:** `cd backend && uv run pytest -q` — all tests pass (model, signing, endpoints, register, contract, plus prior auth/stories/profiles/sessions).
- [ ] **Client suite green:** `flutter test` — all tests pass.
- [ ] **Analyzer clean:** `flutter analyze 2>&1 | grep 'error •'` — no output.
- [ ] **Manual end-to-end (optional, on request only — do not run `flutter run` without explicit instruction):**
  1. `cd backend && docker compose up -d db && uv run alembic upgrade head && uv run python seed.py`
  2. Drop `aud_seg_bunny_p1_1.m4a` into `backend/storage/audio/`, then `uv run python register_assets.py`.
  3. `uv run uvicorn app.main:app`
  4. `flutter run --dart-define=API_BASE_URL=http://localhost:8000` → page 1 of "Bunny and the Moon" plays the registered clip; un-recorded segments fall back to TTS and the fallback banner is truthful.

---

## Notes / deferred (not in this slice)

- Object storage / CDN presigning, image & AR asset serving, the voice-generation worker, per-page gapless audio, offline clip caching, entitlement gating — all separate future slices (spec §3).
- `duration_ms` is left null at registration (no probe dependency); populate it when a later slice needs it.
