# Capture-to-Story Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user scan several physical pages in a row and save them as a new, backend-persisted story that appears in the library and is narrated in the OpenAI voice by the normal player.

**Architecture:** Authored stories live in the existing `stories` table, distinguished by a nullable `owner_user_id` (NULL = curated/seeded). Because the server writes one `NarrationSegment` per page, an authored story deserialises into exactly the same `StoryDetail` shape as a curated one, so the player needs no structural change - only a third audio source. A new Flutter `story_composer` feature owns the multi-page draft and reuses the existing `ScanService`. On Android the ML Kit scanner is promoted out of `src/debug` so the feature ships in release; the ARCore character reader stays debug-only.

**Tech Stack:** FastAPI, SQLAlchemy 2.0, Alembic, Pydantic v2, Postgres 16, `uv`; Flutter with Riverpod 3, go_router 17, freezed 3, dio, just_audio, flutter_tts; Kotlin + ML Kit on Android.

**Spec:** `docs/superpowers/specs/2026-08-23-capture-to-story-design.md`

## Global Constraints

- Ownership predicate, used verbatim everywhere a story is read: `owner_user_id IS NULL OR owner_user_id = :user_id`.
- Every ownership failure returns **404, never 403**. A 403 confirms the id exists.
- Migration `0004` adds **no** `ondelete` to the new FK. No content-table FK in this schema has one.
- Authored slug format is `authored-<uuid4>`. The `authored-` prefix is reserved; no seed file may use it.
- Page text limit is **4000 characters**, matching `ConfirmedText` in `backend/app/routers/tts.py:12`.
- `page_number` must be contiguous `1..N` - no gaps, no duplicates.
- Max **50 pages** per story, **100 authored stories** per user, title **1-120** chars.
- Every authored `NarrationSegment` has `sort_order=0`, `audio_asset_id=NULL`, `speaker_key="narrator"`.
- The narration fetcher is engaged **only** when `story.isAuthored` is true.
- Android: `com.google.ar:core`, `io.github.sceneview:arsceneview` and all Compose dependencies stay `debugImplementation`. The release manifest must keep **zero AR entries**.
- Backend tests run against real Postgres (`backend/tests/conftest.py`). Do not mock the DB.
- Run `flutter analyze` after Dart changes. The pre-existing `narration_player.dart:84` `unnecessary_non_null_assertion` warning is expected and is not a regression.
- Do not modify `lib/features/scan_any_page/scan_any_page_controller.dart`, `lib/features/scan_any_page/scan_any_page_screen.dart`, or the debug "Scan any page" button at `lib/features/library/library_screen.dart:52-62`.

---

## Task 1: Owner column, migration, and `is_authored` on the wire

**Files:**
- Create: `backend/migrations/versions/0004_authored_stories.py`
- Modify: `backend/app/models/__init__.py:65-84` (the `Story` model)
- Modify: `backend/app/schemas/__init__.py` (`StoryOut`)
- Test: `backend/tests/test_authored_stories.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `Story.owner_user_id: Mapped[str | None]`; `StoryOut.is_authored: bool`; migration revision id `0004`.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_authored_stories.py`:

```python
import uuid

from app.models import Story


def _auth(client, device_id="d1"):
    token = client.post("/v1/auth/device", json={"device_id": device_id}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def test_story_model_has_nullable_owner(db):
    story = Story(
        id=str(uuid.uuid4()), title="t", slug="authored-" + str(uuid.uuid4()),
        age_min=3, age_max=8, language_code="en", duration_seconds=0,
        content_status="published", themes=[],
    )
    db.add(story)
    db.flush()
    assert story.owner_user_id is None


def test_curated_story_reports_is_authored_false(client, seeded):
    resp = client.get("/v1/stories", headers=_auth(client))
    assert resp.status_code == 200
    assert all(s["is_authored"] is False for s in resp.json()["stories"])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && uv run pytest tests/test_authored_stories.py -v`
Expected: FAIL - `AttributeError: 'Story' object has no attribute 'owner_user_id'` and `KeyError: 'is_authored'`.

- [ ] **Step 3: Add the model column**

In `backend/app/models/__init__.py`, inside `class Story`, after the `themes` column and before the `pages` relationship:

```python
    owner_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id"), nullable=True, index=True
    )
```

- [ ] **Step 4: Write the migration**

Create `backend/migrations/versions/0004_authored_stories.py`:

```python
"""authored stories: nullable owner on stories

Revision ID: 0004
Revises: 0003
"""
import sqlalchemy as sa
from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("stories", sa.Column("owner_user_id", sa.String(), nullable=True))
    # No ondelete: no content-table FK in this schema declares one, so a
    # DB-level user delete would cascade into stories and then fail against
    # story_pages. There is no user-delete endpoint today.
    op.create_foreign_key(
        "fk_stories_owner_user_id", "stories", "users", ["owner_user_id"], ["id"]
    )
    op.create_index("ix_stories_owner_user_id", "stories", ["owner_user_id"])


def downgrade() -> None:
    op.drop_index("ix_stories_owner_user_id", table_name="stories")
    op.drop_constraint("fk_stories_owner_user_id", "stories", type_="foreignkey")
    op.drop_column("stories", "owner_user_id")
```

Confirm `down_revision` matches the actual revision id in `backend/migrations/versions/0003_assets.py`. If that file uses a different identifier, use its value verbatim.

- [ ] **Step 5: Add `is_authored` to the DTO**

In `backend/app/schemas/__init__.py`, add to `StoryOut` after `is_unlocked`:

```python
    is_authored: bool = False
```

`StoryOut` is `from_attributes=True`, and `Story` has no `is_authored` attribute, so add a computed property to the ORM model instead - in `backend/app/models/__init__.py`, inside `class Story`:

```python
    @property
    def is_authored(self) -> bool:
        return self.owner_user_id is not None
```

This makes `is_authored` appear in **both** `LibraryResponse` entries and the `story` object inside `StoryDetailResponse`, because both use `StoryOut`. The player reads its `Story` from `GET /v1/stories/{id}`; if the detail response omitted the field it would decode to `false` and the narration fetcher would never engage.

- [ ] **Step 6: Run the migration and the tests**

Run:
```bash
cd backend && uv run alembic upgrade head && uv run pytest tests/ -v
```
Expected: migration applies; all tests PASS including the two new ones and the existing `test_stories.py`.

- [ ] **Step 7: Commit**

```bash
git add backend/migrations/versions/0004_authored_stories.py backend/app/models/__init__.py backend/app/schemas/__init__.py backend/tests/test_authored_stories.py
git commit -m "feat(backend): add nullable stories.owner_user_id and is_authored DTO field"
```

---

## Task 2: Ownership filtering on library list and story detail

**Files:**
- Modify: `backend/app/repositories/stories.py:10` (`list_published`), `:23` (`get_detail`)
- Modify: `backend/app/routers/stories.py:17,27`
- Test: `backend/tests/test_authored_stories.py`

**Interfaces:**
- Consumes: `Story.owner_user_id` from Task 1.
- Produces: `list_published(db, user_id, age_band, language) -> list[Story]`; `get_detail(db, user_id, story_id) -> dict | None`.

- [ ] **Step 1: Write the failing test**

Append to `backend/tests/test_authored_stories.py`:

```python
import uuid as _uuid

from app.auth import decode_token


def _make_authored(db, owner_user_id, title="Mine"):
    story = Story(
        id=str(_uuid.uuid4()), title=title, slug="authored-" + str(_uuid.uuid4()),
        age_min=3, age_max=8, language_code="en", duration_seconds=60,
        content_status="published", themes=[], owner_user_id=owner_user_id,
    )
    db.add(story)
    db.flush()
    return story


def _user_id_for(client, device_id):
    token = client.post("/v1/auth/device", json={"device_id": device_id}).json()["token"]
    return decode_token(token), {"Authorization": f"Bearer {token}"}


def test_owner_sees_own_authored_story_in_library(client, db, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    _make_authored(db, uid, title="Owner Story")
    titles = [s["title"] for s in client.get("/v1/stories", headers=headers).json()["stories"]]
    assert "Owner Story" in titles


def test_other_user_does_not_see_authored_story_in_library(client, db, seeded):
    owner_uid, _ = _user_id_for(client, "owner-device")
    _make_authored(db, owner_uid, title="Owner Story")
    _, other_headers = _user_id_for(client, "other-device")
    titles = [s["title"] for s in client.get("/v1/stories", headers=other_headers).json()["stories"]]
    assert "Owner Story" not in titles


def test_authored_story_reports_is_authored_true(client, db, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    story = _make_authored(db, uid)
    entry = next(s for s in client.get("/v1/stories", headers=headers).json()["stories"] if s["id"] == story.id)
    assert entry["is_authored"] is True


def test_other_user_gets_404_on_authored_detail(client, db, seeded):
    owner_uid, _ = _user_id_for(client, "owner-device")
    story = _make_authored(db, owner_uid)
    _, other_headers = _user_id_for(client, "other-device")
    assert client.get(f"/v1/stories/{story.id}", headers=other_headers).status_code == 404


def test_owner_gets_200_on_own_authored_detail(client, db, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    story = _make_authored(db, uid)
    assert client.get(f"/v1/stories/{story.id}", headers=headers).status_code == 200
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && uv run pytest tests/test_authored_stories.py -v`
Expected: FAIL - `test_other_user_does_not_see_authored_story_in_library` and `test_other_user_gets_404_on_authored_detail` both fail because no filtering exists yet.

- [ ] **Step 3: Filter in the repository**

In `backend/app/repositories/stories.py`, replace `list_published` and the opening of `get_detail`:

```python
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models import ArScene, NarrationSegment, Question, Story, StoryPage

# Age bands -> (min, max) per enums.dart
_BANDS = {"3-4": (3, 4), "5-6": (5, 6), "7-8": (7, 8)}


def _visible_to(user_id: str):
    """Curated stories (no owner) plus this user's own authored stories."""
    return or_(Story.owner_user_id.is_(None), Story.owner_user_id == user_id)


def list_published(db: Session, user_id: str, age_band: str | None,
                   language: str | None) -> list[Story]:
    stmt = select(Story).where(Story.content_status == "published", _visible_to(user_id))
    if language:
        stmt = stmt.where(Story.language_code == language)
    stories = list(db.scalars(stmt))
    if age_band and age_band in _BANDS:
        lo, hi = _BANDS[age_band]
        stories = [s for s in stories if s.age_min <= hi and s.age_max >= lo]
    return stories


def get_detail(db: Session, user_id: str, story_id: str) -> dict | None:
    story = db.get(Story, story_id)
    if story is None:
        return None
    if story.owner_user_id is not None and story.owner_user_id != user_id:
        return None  # 404, not 403 - a 403 confirms the id exists
```

Leave the rest of `get_detail` (the pages/segments/ar_scenes/questions queries and the return dict) exactly as it is.

- [ ] **Step 4: Pass the user through the router**

In `backend/app/routers/stories.py`, change both handlers to bind the user instead of discarding it:

```python
@router.get("", response_model=LibraryResponse)
def library(
    age_band: str | None = None,
    language: str | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> LibraryResponse:
    return LibraryResponse(stories=repo.list_published(db, user.id, age_band, language))


@router.get("/{story_id}", response_model=StoryDetailResponse)
def detail(
    story_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> StoryDetailResponse:
    payload = repo.get_detail(db, user.id, story_id)
    if payload is None:
        raise HTTPException(status_code=404, detail="story not found")
    return payload
```

- [ ] **Step 5: Run the tests**

Run: `cd backend && uv run pytest tests/ -v`
Expected: PASS, including the untouched `tests/test_stories.py` and `tests/test_contract.py`.

- [ ] **Step 6: Commit**

```bash
git add backend/app/repositories/stories.py backend/app/routers/stories.py backend/tests/test_authored_stories.py
git commit -m "feat(backend): filter library and detail by story ownership"
```

---

## Task 3: Close the session-start and image-target ownership leaks

**Files:**
- Modify: `backend/app/routers/sessions.py:24`
- Modify: `backend/app/repositories/manifests.py:11`
- Modify: `backend/app/routers/manifests.py:13`
- Test: `backend/tests/test_authored_stories.py`

**Interfaces:**
- Consumes: `_visible_to` / ownership rule from Task 2.
- Produces: `build_image_target_manifest(db, user_id, story_id) -> ImageTargetManifest | None`.

Neither of these leaks content, but both are existence oracles that break the 404-everywhere contract. The session one also matters for correctness: a session another user created against an authored story would permanently block its delete in Task 5.

- [ ] **Step 1: Write the failing test**

Append to `backend/tests/test_authored_stories.py`:

```python
def test_other_user_cannot_start_session_on_authored_story(client, db, seeded):
    owner_uid, _ = _user_id_for(client, "owner-device")
    story = _make_authored(db, owner_uid)
    _, other_headers = _user_id_for(client, "other-device")
    profile = client.post(
        "/v1/child-profiles",
        json={"id": str(_uuid.uuid4()), "age_band": "5-6"},
        headers=other_headers,
    ).json()
    resp = client.post(
        "/v1/story-sessions",
        json={"child_profile_id": profile["id"], "story_id": story.id},
        headers=other_headers,
    )
    assert resp.status_code == 404


def test_other_user_gets_404_on_authored_image_target_manifest(client, db, seeded):
    owner_uid, _ = _user_id_for(client, "owner-device")
    story = _make_authored(db, owner_uid)
    _, other_headers = _user_id_for(client, "other-device")
    resp = client.get(f"/v1/stories/{story.id}/image-target-manifest", headers=other_headers)
    assert resp.status_code == 404
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && uv run pytest tests/test_authored_stories.py -k "cannot_start_session or image_target" -v`
Expected: FAIL - session start returns 200, manifest returns 200.

- [ ] **Step 3: Guard session start**

In `backend/app/routers/sessions.py`, replace the bare existence check in `start_session`:

```python
    story = db.get(Story, body.story_id)
    if story is None or (
        story.owner_user_id is not None and story.owner_user_id != user.id
    ):
        raise HTTPException(status_code=404, detail="story not found")
```

- [ ] **Step 4: Guard the image-target manifest**

In `backend/app/repositories/manifests.py`, change the signature and the guard:

```python
def build_image_target_manifest(
    db: Session, user_id: str, story_id: str
) -> ImageTargetManifest | None:
    story = db.get(Story, story_id)
    if story is None:
        return None
    if story.owner_user_id is not None and story.owner_user_id != user_id:
        return None
```

Leave the rest of the function unchanged.

In `backend/app/routers/manifests.py`, bind the user and pass it through. The handler currently discards it as `_: User = Depends(get_current_user)`; change that to `user: User = Depends(get_current_user)` and call `build_image_target_manifest(db, user.id, story_id)`.

- [ ] **Step 5: Run the tests**

Run: `cd backend && uv run pytest tests/ -v`
Expected: PASS, including the untouched `tests/test_manifests.py` and `tests/test_sessions.py`.

- [ ] **Step 6: Commit**

```bash
git add backend/app/routers/sessions.py backend/app/repositories/manifests.py backend/app/routers/manifests.py backend/tests/test_authored_stories.py
git commit -m "fix(backend): close story-ownership leaks in session start and image-target manifest"
```

---

## Task 4: `POST /v1/stories`

**Files:**
- Modify: `backend/app/schemas/__init__.py`
- Modify: `backend/app/repositories/stories.py`
- Modify: `backend/app/routers/stories.py`
- Test: `backend/tests/test_authored_stories.py`

**Interfaces:**
- Consumes: `Story.owner_user_id` (Task 1), ownership filtering (Task 2).
- Produces: `CreateStoryRequest`, `CreateStoryPage` Pydantic models; `create_authored(db, user_id, payload) -> Story`; `count_authored(db, user_id) -> int`.

- [ ] **Step 1: Write the failing test**

Append to `backend/tests/test_authored_stories.py`:

```python
def _payload(pages=None, title="My Book", language="en"):
    pages = pages if pages is not None else [
        {"page_number": 1, "page_text": "Once upon a time there was a fox."},
        {"page_number": 2, "page_text": "The fox found a red balloon."},
    ]
    return {"title": title, "language_code": language, "pages": pages}


def test_create_story_returns_it_and_sets_owner(client, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    resp = client.post("/v1/stories", json=_payload(), headers=headers)
    assert resp.status_code == 201
    body = resp.json()
    assert body["title"] == "My Book"
    assert body["is_authored"] is True
    assert body["slug"].startswith("authored-")
    assert body["duration_seconds"] >= 60


def test_created_story_round_trips_with_one_segment_per_page(client, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    story_id = client.post("/v1/stories", json=_payload(), headers=headers).json()["id"]
    detail = client.get(f"/v1/stories/{story_id}", headers=headers).json()
    assert len(detail["pages"]) == 2
    assert len(detail["segments"]) == 2
    assert [p["page_number"] for p in detail["pages"]] == [1, 2]
    for seg in detail["segments"]:
        assert seg["speaker_key"] == "narrator"
        assert seg["audio_asset_id"] is None
        assert seg["sort_order"] == 0
    texts = {s["text"] for s in detail["segments"]}
    assert "The fox found a red balloon." in texts


def test_created_story_appears_in_library(client, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    client.post("/v1/stories", json=_payload(), headers=headers)
    titles = [s["title"] for s in client.get("/v1/stories", headers=headers).json()["stories"]]
    assert "My Book" in titles


def test_create_requires_auth(client, seeded):
    assert client.post("/v1/stories", json=_payload()).status_code == 401


def test_create_rejects_empty_pages(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    assert client.post("/v1/stories", json=_payload(pages=[]), headers=headers).status_code == 422


def test_create_rejects_too_many_pages(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    pages = [{"page_number": i + 1, "page_text": "x"} for i in range(51)]
    assert client.post("/v1/stories", json=_payload(pages=pages), headers=headers).status_code == 422


def test_create_rejects_non_contiguous_page_numbers(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    pages = [{"page_number": 1, "page_text": "a"}, {"page_number": 3, "page_text": "b"}]
    assert client.post("/v1/stories", json=_payload(pages=pages), headers=headers).status_code == 422


def test_create_rejects_duplicate_page_numbers(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    pages = [{"page_number": 1, "page_text": "a"}, {"page_number": 1, "page_text": "b"}]
    assert client.post("/v1/stories", json=_payload(pages=pages), headers=headers).status_code == 422


def test_create_rejects_overlong_page_text(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    pages = [{"page_number": 1, "page_text": "x" * 4001}]
    assert client.post("/v1/stories", json=_payload(pages=pages), headers=headers).status_code == 422


def test_create_rejects_blank_title(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    assert client.post("/v1/stories", json=_payload(title="   "), headers=headers).status_code == 422


def test_create_rejects_unsupported_language(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    assert client.post("/v1/stories", json=_payload(language="fr"), headers=headers).status_code == 422


def test_create_enforces_story_cap(client, db, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    for _ in range(100):
        _make_authored(db, uid)
    db.flush()
    assert client.post("/v1/stories", json=_payload(), headers=headers).status_code == 409
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && uv run pytest tests/test_authored_stories.py -k create -v`
Expected: FAIL - all return 405 Method Not Allowed, since `POST /v1/stories` does not exist.

- [ ] **Step 3: Add the request schemas**

In `backend/app/schemas/__init__.py`, add near the other story schemas:

```python
from typing import Annotated, Any

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

AuthoredTitle = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
AuthoredPageText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4000)]


class CreateStoryPage(BaseModel):
    page_number: int = Field(ge=1, le=50)
    page_text: AuthoredPageText


class CreateStoryRequest(BaseModel):
    title: AuthoredTitle
    language_code: str = "en"
    pages: list[CreateStoryPage] = Field(min_length=1, max_length=50)

    @model_validator(mode="after")
    def _check(self) -> "CreateStoryRequest":
        if self.language_code not in ("en", "vi"):
            raise ValueError("language_code must be 'en' or 'vi'")
        numbers = [p.page_number for p in self.pages]
        if sorted(numbers) != list(range(1, len(numbers) + 1)):
            raise ValueError("page_number must be contiguous 1..N with no duplicates")
        return self
```

Keep the existing `from typing import Any` import working - merge the `Annotated` import into it rather than duplicating the line.

- [ ] **Step 4: Add the repository function**

In `backend/app/repositories/stories.py`, add at the end:

```python
import uuid

from app.config import settings

_WORDS_PER_MINUTE = 130
_MAX_AUTHORED_PER_USER = 100


def count_authored(db: Session, user_id: str) -> int:
    return len(list(db.scalars(select(Story.id).where(Story.owner_user_id == user_id))))


def _estimated_duration_seconds(texts: list[str]) -> int:
    words = sum(len(t.split()) for t in texts)
    return max(60, round(words / _WORDS_PER_MINUTE * 60))


def create_authored(db: Session, user_id: str, payload) -> Story:
    """Write story + pages + one narration segment per page in one transaction."""
    ordered = sorted(payload.pages, key=lambda p: p.page_number)
    story_id = str(uuid.uuid4())
    story = Story(
        id=story_id,
        title=payload.title,
        slug=f"authored-{uuid.uuid4()}",
        description=None,
        age_min=3,
        age_max=8,
        language_code=payload.language_code,
        duration_seconds=_estimated_duration_seconds([p.page_text for p in ordered]),
        cover_asset_id=None,
        content_status="published",
        rights_owner_id=None,
        themes=[],
        owner_user_id=user_id,
    )
    db.add(story)
    db.flush()

    for page in ordered:
        page_id = str(uuid.uuid4())
        db.add(StoryPage(
            id=page_id, story_id=story_id, page_number=page.page_number,
            page_text=page.page_text, page_image_asset_id=None, image_target_id=None,
        ))
        db.flush()
        db.add(NarrationSegment(
            id=str(uuid.uuid4()), story_id=story_id, page_id=page_id,
            speaker_key="narrator", text=page.page_text,
            voice_id=settings.openai_tts_voice, emotion=None, speed=1.0,
            audio_asset_id=None, start_ms=0, end_ms=0, sort_order=0,
        ))
    db.commit()
    db.refresh(story)
    return story
```

- [ ] **Step 5: Add the route**

In `backend/app/routers/stories.py`:

```python
@router.post("", response_model=StoryOut, status_code=201)
def create(
    body: CreateStoryRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> StoryOut:
    if repo.count_authored(db, user.id) >= 100:
        raise HTTPException(status_code=409, detail="authored story limit reached")
    return repo.create_authored(db, user.id, body)
```

Add `CreateStoryRequest` and `StoryOut` to the existing `from app.schemas import ...` line.

- [ ] **Step 6: Run the tests**

Run: `cd backend && uv run pytest tests/ -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/app/schemas/__init__.py backend/app/repositories/stories.py backend/app/routers/stories.py backend/tests/test_authored_stories.py
git commit -m "feat(backend): add POST /v1/stories for authored stories"
```

---

## Task 5: `DELETE /v1/stories/{story_id}`

**Files:**
- Modify: `backend/app/repositories/stories.py`
- Modify: `backend/app/routers/stories.py`
- Test: `backend/tests/test_authored_stories.py`

**Interfaces:**
- Consumes: `create_authored` (Task 4).
- Produces: `delete_authored(db, user_id, story_id) -> bool`.

**The naive implementation is a guaranteed 500.** `Story` has `cascade="all, delete-orphan"` relationships to pages, segments, ar_scenes and questions, but **no relationship to `StorySession`**, and `story_sessions.story_id` is a bare FK with no `ondelete` (`backend/migrations/versions/0001_initial.py:136`). The player opens a session on every read, so `create -> read -> delete` raises a Postgres FK violation. The test below must be **read-then-delete**; a create-then-delete test passes while the bug is fully present.

- [ ] **Step 1: Write the failing test**

Append to `backend/tests/test_authored_stories.py`:

```python
from app.models import InteractionEvent, StorySession


def _profile_for(client, headers):
    return client.post(
        "/v1/child-profiles",
        json={"id": str(_uuid.uuid4()), "age_band": "5-6"},
        headers=headers,
    ).json()


def test_delete_after_reading_succeeds_and_clears_sessions(client, db, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    story_id = client.post("/v1/stories", json=_payload(), headers=headers).json()["id"]
    profile = _profile_for(client, headers)

    # Read it, exactly as the player does: this creates a story_session and a
    # story_started interaction_event.
    session = client.post(
        "/v1/story-sessions",
        json={"child_profile_id": profile["id"], "story_id": story_id},
        headers=headers,
    ).json()
    assert db.get(StorySession, session["id"]) is not None

    resp = client.delete(f"/v1/stories/{story_id}", headers=headers)
    assert resp.status_code == 204

    assert db.get(StorySession, session["id"]) is None
    remaining_events = list(db.scalars(
        select(InteractionEvent).where(InteractionEvent.story_session_id == session["id"])
    ))
    assert remaining_events == []
    assert client.get(f"/v1/stories/{story_id}", headers=headers).status_code == 404


def test_delete_cascades_pages_and_segments(client, db, seeded):
    _, headers = _user_id_for(client, "owner-device")
    story_id = client.post("/v1/stories", json=_payload(), headers=headers).json()["id"]
    client.delete(f"/v1/stories/{story_id}", headers=headers)
    assert list(db.scalars(select(StoryPage).where(StoryPage.story_id == story_id))) == []
    assert list(db.scalars(select(NarrationSegment).where(NarrationSegment.story_id == story_id))) == []


def test_delete_is_owner_only(client, seeded):
    _, owner_headers = _user_id_for(client, "owner-device")
    story_id = client.post("/v1/stories", json=_payload(), headers=owner_headers).json()["id"]
    _, other_headers = _user_id_for(client, "other-device")
    assert client.delete(f"/v1/stories/{story_id}", headers=other_headers).status_code == 404
    assert client.get(f"/v1/stories/{story_id}", headers=owner_headers).status_code == 200


def test_delete_rejects_curated_story(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    curated_id = client.get("/v1/stories", headers=headers).json()["stories"][0]["id"]
    assert client.delete(f"/v1/stories/{curated_id}", headers=headers).status_code == 404
    assert client.get(f"/v1/stories/{curated_id}", headers=headers).status_code == 200


def test_delete_unknown_story_404s(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    assert client.delete(f"/v1/stories/{_uuid.uuid4()}", headers=headers).status_code == 404
```

Add `from app.models import NarrationSegment, StoryPage` and `from sqlalchemy import select` to the test file's imports.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && uv run pytest tests/test_authored_stories.py -k delete -v`
Expected: FAIL - 405 Method Not Allowed, since the route does not exist.

- [ ] **Step 3: Write the repository delete**

In `backend/app/repositories/stories.py`, add:

```python
from app.models import InteractionEvent, StorySession


def delete_authored(db: Session, user_id: str, story_id: str) -> bool:
    """Delete a story the user authored. Returns False if it is unknown,
    curated, or owned by someone else - the router turns that into a 404.
    """
    story = db.get(Story, story_id)
    if story is None or story.owner_user_id != user_id:
        return False

    # story_sessions.story_id is a bare FK with no ondelete, and Story has no
    # ORM relationship to StorySession, so nothing cascades here. Clear the
    # sessions (and their events) first or Postgres raises a FK violation for
    # any story that was ever opened in the player.
    session_ids = list(db.scalars(
        select(StorySession.id).where(StorySession.story_id == story_id)
    ))
    if session_ids:
        db.query(InteractionEvent).filter(
            InteractionEvent.story_session_id.in_(session_ids)
        ).delete(synchronize_session=False)
        db.query(StorySession).filter(
            StorySession.id.in_(session_ids)
        ).delete(synchronize_session=False)

    # pages / segments / ar_scenes / questions go via the ORM cascades declared
    # on the Story model.
    db.delete(story)
    db.commit()
    return True
```

- [ ] **Step 4: Add the route**

In `backend/app/routers/stories.py`:

```python
@router.delete("/{story_id}", status_code=204)
def delete(
    story_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Response:
    if not repo.delete_authored(db, user.id, story_id):
        raise HTTPException(status_code=404, detail="story not found")
    return Response(status_code=204)
```

Add `from fastapi import Response` to the imports.

- [ ] **Step 5: Run the tests**

Run: `cd backend && uv run pytest tests/ -v`
Expected: PASS, all of them.

- [ ] **Step 6: Commit**

```bash
git add backend/app/repositories/stories.py backend/app/routers/stories.py backend/tests/test_authored_stories.py
git commit -m "feat(backend): add owner-only DELETE /v1/stories with session cleanup"
```

---

## Task 6: `Story.isAuthored` on the Flutter model

**Files:**
- Modify: `lib/data/models/story.dart`
- Test: `test/content_parsing_test.dart`

**Interfaces:**
- Consumes: `is_authored` from Task 1.
- Produces: `Story.isAuthored: bool` (defaults `false`).

`build.yaml` sets `field_rename: snake`, so `isAuthored` maps to `is_authored` with no annotation.

- [ ] **Step 1: Write the failing test**

Append to `test/content_parsing_test.dart`:

```dart
  test('Story.isAuthored defaults to false and decodes is_authored', () {
    const base = {
      'id': 's1',
      'title': 'T',
      'slug': 'authored-abc',
      'age_min': 3,
      'age_max': 8,
      'language_code': 'en',
      'duration_seconds': 60,
      'content_status': 'published',
      'themes': <String>[],
    };
    expect(Story.fromJson({...base}).isAuthored, isFalse);
    expect(Story.fromJson({...base, 'is_authored': true}).isAuthored, isTrue);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/content_parsing_test.dart`
Expected: FAIL - `The getter 'isAuthored' isn't defined for the type 'Story'`.

- [ ] **Step 3: Add the field**

In `lib/data/models/story.dart`, inside the `const factory Story({...})`, after `isUnlocked`:

```dart
    /// True when this story was captured by the user rather than curated
    /// (server-side `owner_user_id IS NOT NULL`). Gates the narration fetcher.
    @Default(false) bool isAuthored,
```

- [ ] **Step 4: Regenerate and run**

Run:
```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/content_parsing_test.dart
```
Expected: codegen succeeds, test PASSES.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/story.dart lib/data/models/story.freezed.dart lib/data/models/story.g.dart test/content_parsing_test.dart
git commit -m "feat(client): add Story.isAuthored"
```

---

## Task 7: `AuthoredStoryRepository` and its HTTP implementation

**Files:**
- Create: `lib/data/repositories/authored_story_repository.dart`
- Create: `lib/data/repositories/http_authored_story_repository.dart`
- Create: `lib/features/story_composer/story_draft.dart`
- Modify: `lib/core/di.dart`
- Test: `test/http_repositories_test.dart`

**Interfaces:**
- Consumes: `POST /v1/stories`, `DELETE /v1/stories/{id}` (Tasks 4-5); `ApiClient`.
- Produces:
  - `class StoryDraft { final String title; final String languageCode; final List<DraftPage> pages; }`
  - `class DraftPage { final String localId; final String text; }`
  - `abstract interface class AuthoredStoryRepository { Future<Story> createStory(StoryDraft draft); Future<void> deleteStory(String storyId); }`
  - `final class AuthoredStoryFailure implements Exception { final String code; }`
  - `final authoredStoryRepositoryProvider = Provider<AuthoredStoryRepository>(...)`

Kept separate from `StoryRepository` because reads need no change, and widening `StoryRepository` would force stub methods onto `LocalStoryRepository`, which nothing references.

- [ ] **Step 1: Write the draft value type**

Create `lib/features/story_composer/story_draft.dart`:

```dart
import 'package:flutter/foundation.dart';

/// One captured page held in memory while composing. Never persisted.
@immutable
class DraftPage {
  const DraftPage({required this.localId, required this.text});

  final String localId;
  final String text;

  DraftPage copyWith({String? text}) =>
      DraftPage(localId: localId, text: text ?? this.text);

  @override
  bool operator ==(Object other) =>
      other is DraftPage && other.localId == localId && other.text == text;

  @override
  int get hashCode => Object.hash(localId, text);
}

/// An in-progress authored story. Lost if the app is killed mid-capture:
/// draft persistence is deliberately out of scope for this slice.
@immutable
class StoryDraft {
  const StoryDraft({
    this.title = '',
    this.languageCode = 'en',
    this.pages = const <DraftPage>[],
  });

  final String title;
  final String languageCode;
  final List<DraftPage> pages;

  /// Save is only permitted with a real title and at least one page; the
  /// backend enforces the same rule and would return 422 otherwise.
  bool get isSaveable => title.trim().isNotEmpty && pages.isNotEmpty;

  StoryDraft copyWith({
    String? title,
    String? languageCode,
    List<DraftPage>? pages,
  }) =>
      StoryDraft(
        title: title ?? this.title,
        languageCode: languageCode ?? this.languageCode,
        pages: pages ?? this.pages,
      );

  /// Wire format for POST /v1/stories. Page numbers are assigned from list
  /// order, so they are always contiguous 1..N regardless of edits.
  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'language_code': languageCode,
        'pages': [
          for (var i = 0; i < pages.length; i++)
            {'page_number': i + 1, 'page_text': pages[i].text.trim()},
        ],
      };

  @override
  bool operator ==(Object other) =>
      other is StoryDraft &&
      other.title == title &&
      other.languageCode == languageCode &&
      listEquals(other.pages, pages);

  @override
  int get hashCode => Object.hash(title, languageCode, Object.hashAll(pages));
}
```

Numbering from list order rather than trusting a stored index is what guarantees the contiguity rule from Task 4 can never be violated by a remove-then-save.

- [ ] **Step 2: Write the failing test**

Append to `test/http_repositories_test.dart`, following the existing fake-Dio pattern already in that file:

```dart
  group('HttpAuthoredStoryRepository', () {
    test('createStory posts contiguous page numbers from list order', () async {
      late Map<String, dynamic> captured;
      final repo = HttpAuthoredStoryRepository(
        fakeApiClient(onPost: (path, data) {
          captured = data as Map<String, dynamic>;
          return {
            'id': 'new-id', 'title': 'My Book', 'slug': 'authored-x',
            'age_min': 3, 'age_max': 8, 'language_code': 'en',
            'duration_seconds': 60, 'content_status': 'published',
            'themes': <String>[], 'is_authored': true,
          };
        }),
      );

      final story = await repo.createStory(const StoryDraft(
        title: '  My Book  ',
        pages: [
          DraftPage(localId: 'a', text: 'page one'),
          DraftPage(localId: 'b', text: 'page two'),
        ],
      ));

      expect(captured['title'], 'My Book');
      expect(
        (captured['pages'] as List).map((p) => p['page_number']).toList(),
        [1, 2],
      );
      expect(story.isAuthored, isTrue);
    });

    test('createStory maps a 409 to a quota failure code', () async {
      final repo = HttpAuthoredStoryRepository(
        fakeApiClient(onPost: (_, _) => throw dioError(409)),
      );
      expect(
        () => repo.createStory(const StoryDraft(
          title: 'T',
          pages: [DraftPage(localId: 'a', text: 'x')],
        )),
        throwsA(isA<AuthoredStoryFailure>()
            .having((e) => e.code, 'code', 'quota_reached')),
      );
    });

    test('deleteStory treats a 404 as success', () async {
      final repo = HttpAuthoredStoryRepository(
        fakeApiClient(onDelete: (_) => throw dioError(404)),
      );
      await expectLater(repo.deleteStory('gone'), completes);
    });
  });
```

If `fakeApiClient` and `dioError` helpers do not already exist in that file, write them alongside the existing fakes using the same construction style the file already uses for `HttpStoryRepository`.

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/http_repositories_test.dart`
Expected: FAIL - `HttpAuthoredStoryRepository` is not defined.

- [ ] **Step 4: Write the interface**

Create `lib/data/repositories/authored_story_repository.dart`:

```dart
import '../../features/story_composer/story_draft.dart';
import '../models/models.dart';

/// Write access for user-authored stories (POST/DELETE /v1/stories).
///
/// Deliberately separate from [StoryRepository]: reads need no change at all,
/// because authored stories come back through GET /v1/stories like any other.
abstract interface class AuthoredStoryRepository {
  /// Creates the story server-side and returns it as the library sees it.
  Future<Story> createStory(StoryDraft draft);

  /// Deletes an authored story. A 404 is treated as success - the story is
  /// gone either way.
  Future<void> deleteStory(String storyId);
}

final class AuthoredStoryFailure implements Exception {
  const AuthoredStoryFailure(this.code);

  final String code;
}
```

- [ ] **Step 5: Write the implementation**

Create `lib/data/repositories/http_authored_story_repository.dart`:

```dart
import 'dart:io';

import 'package:dio/dio.dart';

import '../../features/story_composer/story_draft.dart';
import '../models/models.dart';
import '../sources/api_client.dart';
import 'authored_story_repository.dart';

class HttpAuthoredStoryRepository implements AuthoredStoryRepository {
  HttpAuthoredStoryRepository(this._api);

  final ApiClient _api;

  @override
  Future<Story> createStory(StoryDraft draft) async {
    try {
      final resp = await _api.send(
        () => _api.dio.post('/v1/stories', data: draft.toJson()),
      );
      return Story.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw AuthoredStoryFailure(_failureCode(error));
    }
  }

  @override
  Future<void> deleteStory(String storyId) async {
    try {
      await _api.send(() => _api.dio.delete('/v1/stories/$storyId'));
    } on DioException catch (error) {
      // Already gone is the outcome the caller wanted.
      if (error.response?.statusCode == 404) return;
      throw AuthoredStoryFailure(_failureCode(error));
    }
  }
}

String _failureCode(DioException error) {
  switch (error.response?.statusCode) {
    case 401:
    case 403:
      return 'authentication';
    case 409:
      return 'quota_reached';
    case 422:
      return 'invalid_story';
    case 429:
      return 'rate_limited';
  }
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'timeout';
    case DioExceptionType.connectionError:
      return 'backend_unreachable';
    case DioExceptionType.badCertificate:
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return 'upstream_failed';
    case DioExceptionType.unknown:
      return error.error is SocketException
          ? 'backend_unreachable'
          : 'upstream_failed';
  }
}
```

- [ ] **Step 6: Register the provider**

In `lib/core/di.dart`, add the imports and, next to `storyRepositoryProvider`:

```dart
final authoredStoryRepositoryProvider = Provider<AuthoredStoryRepository>(
  (ref) => HttpAuthoredStoryRepository(ref.watch(apiClientProvider)),
);
```

- [ ] **Step 7: Run tests and analyze**

Run:
```bash
flutter test test/http_repositories_test.dart
flutter analyze 2>&1 | grep 'error •' || echo "no errors"
```
Expected: tests PASS, no analyzer errors.

- [ ] **Step 8: Commit**

```bash
git add lib/data/repositories/authored_story_repository.dart lib/data/repositories/http_authored_story_repository.dart lib/features/story_composer/story_draft.dart lib/core/di.dart test/http_repositories_test.dart
git commit -m "feat(client): add AuthoredStoryRepository and StoryDraft"
```

---

## Task 8: `StoryComposerController`

**Files:**
- Create: `lib/features/story_composer/story_composer_controller.dart`
- Modify: `lib/core/di.dart`
- Test: `test/story_composer_controller_test.dart`

**Interfaces:**
- Consumes: `ScanService` (`lib/features/scan_any_page/native_scan_service.dart`), `AuthoredStoryRepository`, `StoryDraft` (Task 7).
- Produces:
  - `enum StoryComposerPhase { editing, scanning, saving, failure }`
  - `class StoryComposerState { phase, draft, failureCode, savedStoryId }`
  - `class StoryComposerController extends Notifier<StoryComposerState>` with `addPage()`, `setTitle(String)`, `setLanguage(String)`, `editPageText(String localId, String text)`, `removePage(String localId)`, `save()`, `reset()`
  - `typedef StoryComposerDependencies = ({ScanService scanService, AuthoredStoryRepository repository, String languageCode});`
  - `final storyComposerControllerProvider = NotifierProvider.autoDispose.family<...>`

- [ ] **Step 1: Write the failing test**

Create `test/story_composer_controller_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/authored_story_repository.dart';
import 'package:storybook_ar/features/scan_any_page/native_scan_service.dart';
import 'package:storybook_ar/features/story_composer/story_composer_controller.dart';
import 'package:storybook_ar/features/story_composer/story_draft.dart';

class _FakeScanService implements ScanService {
  _FakeScanService(this.responses);

  final List<Object> responses;
  var calls = 0;

  @override
  Future<String> scanAndRecognize() async {
    final response = responses[calls++];
    if (response is Exception) throw response;
    return response as String;
  }
}

class _SlowScanService implements ScanService {
  final completer = Completer<String>();

  @override
  Future<String> scanAndRecognize() => completer.future;
}

class _FakeRepo implements AuthoredStoryRepository {
  _FakeRepo({this.failure});

  final AuthoredStoryFailure? failure;
  StoryDraft? saved;

  @override
  Future<Story> createStory(StoryDraft draft) async {
    if (failure != null) throw failure!;
    saved = draft;
    return const Story(id: 'new', title: 'T', slug: 'authored-x', isAuthored: true);
  }

  @override
  Future<void> deleteStory(String storyId) async {}
}

void main() {
  StoryComposerDependencies deps(ScanService scan, AuthoredStoryRepository repo,
          {String language = 'en'}) =>
      (scanService: scan, repository: repo, languageCode: language);

  test('addPage appends the recognized text', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService(['page one']), _FakeRepo()));

    await container.read(provider.notifier).addPage();

    final state = container.read(provider);
    expect(state.phase, StoryComposerPhase.editing);
    expect(state.draft.pages.single.text, 'page one');
  });

  test('a cancelled scan leaves existing pages intact and shows no error', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService(['page one', ScanCancelled()]), _FakeRepo()));
    final notifier = container.read(provider.notifier);

    await notifier.addPage();
    await notifier.addPage();

    final state = container.read(provider);
    expect(state.phase, StoryComposerPhase.editing);
    expect(state.failureCode, isNull);
    expect(state.draft.pages, hasLength(1));
  });

  test('a failed scan surfaces a scan: code and keeps the draft', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService(['page one', const ScanFailure('no_text')]), _FakeRepo()));
    final notifier = container.read(provider.notifier);

    await notifier.addPage();
    await notifier.addPage();

    final state = container.read(provider);
    expect(state.failureCode, 'scan:no_text');
    expect(state.draft.pages, hasLength(1));
  });

  test('draft is not saveable without a title or without pages', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService(['page one']), _FakeRepo()));
    final notifier = container.read(provider.notifier);

    expect(container.read(provider).draft.isSaveable, isFalse);
    notifier.setTitle('My Book');
    expect(container.read(provider).draft.isSaveable, isFalse);
    await notifier.addPage();
    expect(container.read(provider).draft.isSaveable, isTrue);
  });

  test('removePage drops only the named page', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService(['one', 'two']), _FakeRepo()));
    final notifier = container.read(provider.notifier);

    await notifier.addPage();
    await notifier.addPage();
    final firstId = container.read(provider).draft.pages.first.localId;
    notifier.removePage(firstId);

    expect(container.read(provider).draft.pages.single.text, 'two');
  });

  test('language defaults to the injected profile language', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService([]), _FakeRepo(), language: 'vi'));
    expect(container.read(provider).draft.languageCode, 'vi');
  });

  test('save failure keeps the draft and reports the code', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = storyComposerControllerProvider(deps(
      _FakeScanService(['one']),
      _FakeRepo(failure: const AuthoredStoryFailure('quota_reached')),
    ));
    final notifier = container.read(provider.notifier);

    await notifier.addPage();
    notifier.setTitle('My Book');
    await notifier.save();

    final state = container.read(provider);
    expect(state.phase, StoryComposerPhase.failure);
    expect(state.failureCode, 'save:quota_reached');
    expect(state.draft.pages, hasLength(1));
    expect(state.savedStoryId, isNull);
  });

  test('successful save records the new story id', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repo = _FakeRepo();
    final provider =
        storyComposerControllerProvider(deps(_FakeScanService(['one']), repo));
    final notifier = container.read(provider.notifier);

    await notifier.addPage();
    notifier.setTitle('My Book');
    await notifier.save();

    expect(container.read(provider).savedStoryId, 'new');
    expect(repo.saved!.pages, hasLength(1));
  });

  test('a scan resolving after reset does not write into the new draft', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final scan = _SlowScanService();
    final provider =
        storyComposerControllerProvider(deps(scan, _FakeRepo()));
    final notifier = container.read(provider.notifier);

    final pending = notifier.addPage();
    notifier.reset();
    scan.completer.complete('late text');
    await pending;

    expect(container.read(provider).draft.pages, isEmpty);
  });
}
```

Add `import 'dart:async';` at the top for `Completer`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/story_composer_controller_test.dart`
Expected: FAIL - `story_composer_controller.dart` does not exist.

- [ ] **Step 3: Write the controller**

Create `lib/features/story_composer/story_composer_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/authored_story_repository.dart';
import '../scan_any_page/native_scan_service.dart';
import 'story_draft.dart';

enum StoryComposerPhase { editing, scanning, saving, failure }

class StoryComposerState {
  const StoryComposerState({
    this.phase = StoryComposerPhase.editing,
    this.draft = const StoryDraft(),
    this.failureCode,
    this.savedStoryId,
  });

  final StoryComposerPhase phase;
  final StoryDraft draft;
  final String? failureCode;
  final String? savedStoryId;

  StoryComposerState copyWith({
    StoryComposerPhase? phase,
    StoryDraft? draft,
    Object? failureCode = _unset,
    Object? savedStoryId = _unset,
  }) =>
      StoryComposerState(
        phase: phase ?? this.phase,
        draft: draft ?? this.draft,
        failureCode: identical(failureCode, _unset)
            ? this.failureCode
            : failureCode as String?,
        savedStoryId: identical(savedStoryId, _unset)
            ? this.savedStoryId
            : savedStoryId as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is StoryComposerState &&
      other.phase == phase &&
      other.draft == draft &&
      other.failureCode == failureCode &&
      other.savedStoryId == savedStoryId;

  @override
  int get hashCode => Object.hash(phase, draft, failureCode, savedStoryId);
}

const _unset = Object();

typedef StoryComposerDependencies = ({
  ScanService scanService,
  AuthoredStoryRepository repository,
  String languageCode,
});

class StoryComposerController extends Notifier<StoryComposerState> {
  StoryComposerController({
    required ScanService scanService,
    required AuthoredStoryRepository repository,
    required String languageCode,
  })  : _scanService = scanService,
        _repository = repository,
        _languageCode = languageCode;

  final ScanService _scanService;
  final AuthoredStoryRepository _repository;
  final String _languageCode;

  var _generation = 0;
  var _disposed = false;
  var _nextLocalId = 0;

  @override
  StoryComposerState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    return StoryComposerState(
      draft: StoryDraft(languageCode: _languageCode),
    );
  }

  void setTitle(String title) =>
      state = state.copyWith(draft: state.draft.copyWith(title: title));

  void setLanguage(String languageCode) => state =
      state.copyWith(draft: state.draft.copyWith(languageCode: languageCode));

  void editPageText(String localId, String text) {
    final pages = [
      for (final page in state.draft.pages)
        page.localId == localId ? page.copyWith(text: text) : page,
    ];
    state = state.copyWith(draft: state.draft.copyWith(pages: pages));
  }

  void removePage(String localId) {
    final pages =
        state.draft.pages.where((p) => p.localId != localId).toList();
    state = state.copyWith(draft: state.draft.copyWith(pages: pages));
  }

  Future<void> addPage() async {
    final generation = ++_generation;
    state = state.copyWith(
      phase: StoryComposerPhase.scanning,
      failureCode: null,
    );
    try {
      final text = await _scanService.scanAndRecognize();
      if (!_isCurrent(generation)) return;
      final pages = [
        ...state.draft.pages,
        DraftPage(localId: 'p${_nextLocalId++}', text: text),
      ];
      state = state.copyWith(
        phase: StoryComposerPhase.editing,
        draft: state.draft.copyWith(pages: pages),
        failureCode: null,
      );
    } on ScanCancelled {
      if (!_isCurrent(generation)) return;
      // Backing out of the scanner is not an error; keep what we have.
      state = state.copyWith(
        phase: StoryComposerPhase.editing,
        failureCode: null,
      );
    } on ScanFailure catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: StoryComposerPhase.failure,
        failureCode: 'scan:${error.code}',
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: StoryComposerPhase.failure,
        failureCode: 'scan:unknown',
      );
    }
  }

  Future<void> save() async {
    if (!state.draft.isSaveable) return;
    final generation = ++_generation;
    state = state.copyWith(
      phase: StoryComposerPhase.saving,
      failureCode: null,
    );
    try {
      final story = await _repository.createStory(state.draft);
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: StoryComposerPhase.editing,
        failureCode: null,
        savedStoryId: story.id,
      );
    } on AuthoredStoryFailure catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: StoryComposerPhase.failure,
        failureCode: 'save:${error.code}',
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: StoryComposerPhase.failure,
        failureCode: 'save:unknown',
      );
    }
  }

  void reset() {
    _generation++;
    state = StoryComposerState(draft: StoryDraft(languageCode: _languageCode));
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;
}
```

- [ ] **Step 4: Register the provider**

In `lib/core/di.dart`, mirroring `scanAnyPageControllerProvider`:

```dart
final storyComposerControllerProvider = NotifierProvider.autoDispose.family<
    StoryComposerController, StoryComposerState, StoryComposerDependencies>(
  (dependencies) => StoryComposerController(
    scanService: dependencies.scanService,
    repository: dependencies.repository,
    languageCode: dependencies.languageCode,
  ),
);
```

- [ ] **Step 5: Run tests and analyze**

Run:
```bash
flutter test test/story_composer_controller_test.dart
flutter analyze 2>&1 | grep 'error •' || echo "no errors"
```
Expected: all tests PASS, no analyzer errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/story_composer/story_composer_controller.dart lib/core/di.dart test/story_composer_controller_test.dart
git commit -m "feat(client): add StoryComposerController"
```

---

## Task 9: Composer screen, route, and library entry point

**Files:**
- Create: `lib/features/story_composer/story_composer_screen.dart`
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/library/library_screen.dart` (app bar `actions` only)

**Interfaces:**
- Consumes: `StoryComposerController` (Task 8), `childProfileProvider`, `libraryProvider`.
- Produces: `AppRoutes.createStory = '/create-story'`.

Do **not** touch the debug-only "Scan any page" button at `library_screen.dart:52-62`.

- [ ] **Step 1: Add the route**

In `lib/core/router/app_router.dart`, add to `AppRoutes`:

```dart
  static const createStory = '/create-story';
```

and register it alongside the other routes - **not** wrapped in `if (kDebugMode)`, unlike `scanAnyPage`:

```dart
      GoRoute(
        path: AppRoutes.createStory,
        builder: (_, _) => const StoryComposerScreen(),
      ),
```

- [ ] **Step 2: Write the screen**

Create `lib/features/story_composer/story_composer_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di.dart';
import '../library/library_providers.dart';
import '../profile/profile_providers.dart';
import 'story_composer_controller.dart';

/// Capture several pages and save them as a new story. Reached from the
/// library app bar; not gated on kDebugMode, and not behind the parental gate
/// (deleting a story is gated instead - see the parent dashboard).
class StoryComposerScreen extends ConsumerWidget {
  const StoryComposerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language =
        ref.watch(childProfileProvider).value?.languageCode ?? 'en';
    final dependencies = (
      scanService: ref.watch(scanServiceProvider),
      repository: ref.watch(authoredStoryRepositoryProvider),
      languageCode: language,
    );
    final provider = storyComposerControllerProvider(dependencies);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    ref.listen(provider, (previous, next) {
      if (next.savedStoryId != null &&
          previous?.savedStoryId != next.savedStoryId) {
        ref.invalidate(libraryProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Story saved.')),
        );
        context.go(AppRoutes.home);
      }
    });

    final busy = state.phase == StoryComposerPhase.scanning ||
        state.phase == StoryComposerPhase.saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Create a story')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Story name',
                  border: OutlineInputBorder(),
                ),
                maxLength: 120,
                onChanged: notifier.setTitle,
              ),
            ),
            if (state.failureCode != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _messageFor(state.failureCode!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: state.draft.pages.isEmpty
                  ? const Center(
                      child: Text('Scan a page to start your story.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.draft.pages.length,
                      itemBuilder: (_, i) {
                        final page = state.draft.pages[i];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('Page ${i + 1}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Remove page',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: busy
                                          ? null
                                          : () =>
                                              notifier.removePage(page.localId),
                                    ),
                                  ],
                                ),
                                TextFormField(
                                  key: ValueKey(page.localId),
                                  initialValue: page.text,
                                  maxLines: null,
                                  maxLength: 4000,
                                  onChanged: (text) =>
                                      notifier.editPageText(page.localId, text),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : notifier.addPage,
                      icon: const Icon(Icons.document_scanner_rounded),
                      label: Text(state.phase == StoryComposerPhase.scanning
                          ? 'Scanning…'
                          : 'Add page'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (busy || !state.draft.isSaveable)
                          ? null
                          : notifier.save,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(state.phase == StoryComposerPhase.saving
                          ? 'Saving…'
                          : 'Save story'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _messageFor(String failureCode) {
  if (failureCode == 'scan:no_text') {
    return "We couldn't read any words on that page. Try again with more light.";
  }
  if (failureCode.startsWith('scan:')) {
    return "The scan didn't work. Please try again.";
  }
  if (failureCode == 'save:quota_reached') {
    return 'You have reached the limit for saved stories. Delete one first.';
  }
  if (failureCode == 'save:backend_unreachable') {
    return "We couldn't reach the story service. Check the connection and try again.";
  }
  return "We couldn't save the story. Please try again.";
}
```

Import `AppRoutes` from `../../core/router/app_router.dart`.

- [ ] **Step 3: Add the library entry point**

In `lib/features/library/library_screen.dart`, add a new `IconButton` to the existing `AppBar` `actions` list, **before** the bedtime button:

```dart
          IconButton(
            tooltip: 'Create a story',
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: () => context.push(AppRoutes.createStory),
          ),
```

Change nothing else in this file.

- [ ] **Step 4: Badge authored stories in the grid**

Spec §5.5 requires authored cards to be visually distinguishable. In
`lib/features/library/story_cover.dart`, add a small badge overlay shown only
when `story.isAuthored`:

```dart
        if (story.isAuthored)
          Positioned(
            top: 8,
            left: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text('Made by you', style: TextStyle(fontSize: 11)),
              ),
            ),
          ),
```

Read `story_cover.dart` first and place this inside whatever `Stack` already
renders the cover. If the cover is not built from a `Stack`, wrap the existing
cover widget in one rather than restructuring it.

- [ ] **Step 5: Verify**

Run:
```bash
flutter analyze 2>&1 | grep 'error •' || echo "no errors"
flutter test
```
Expected: no analyzer errors, full suite PASSES.

- [ ] **Step 6: Commit**

```bash
git add lib/features/story_composer/story_composer_screen.dart lib/core/router/app_router.dart lib/features/library/library_screen.dart lib/features/library/story_cover.dart
git commit -m "feat(client): add story composer screen, library entry point, and authored badge"
```

---

## Task 10: Gated delete on the parent dashboard

**Files:**
- Create: `lib/features/dashboard/authored_stories_section.dart`
- Modify: `lib/features/dashboard/parent_dashboard_screen.dart`

**Interfaces:**
- Consumes: `libraryProvider`, `authoredStoryRepositoryProvider` (Task 7), `Story.isAuthored` (Task 6).
- Produces: nothing consumed by later tasks.

Delete lives here, behind `/gate`, rather than as a long-press in the child library - it is destructive and a child must not be able to reach it.

- [ ] **Step 1: Write the section widget**

Create `lib/features/dashboard/authored_stories_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/repositories/authored_story_repository.dart';
import '../library/library_providers.dart';

/// Grown-ups-only management of stories captured in the app. Behind the
/// parental gate because deleting is destructive.
class AuthoredStoriesSection extends ConsumerWidget {
  const AuthoredStoriesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    return library.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (stories) {
        final authored = stories.where((s) => s.isAuthored).toList();
        if (authored.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('Stories you made',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final story in authored)
              ListTile(
                title: Text(story.title),
                subtitle: Text('${story.ageRangeLabel} • captured in the app'),
                trailing: IconButton(
                  tooltip: 'Delete story',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref, story.id, story.title),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String storyId,
    String title,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "$title"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authoredStoryRepositoryProvider).deleteStory(storyId);
      ref.invalidate(libraryProvider);
    } on AuthoredStoryFailure {
      messenger.showSnackBar(
        const SnackBar(content: Text("We couldn't delete that story.")),
      );
    }
  }
}
```

- [ ] **Step 2: Mount it on the dashboard**

Read `lib/features/dashboard/parent_dashboard_screen.dart` first and insert `const AuthoredStoriesSection()` into the existing scrolling column, following whatever layout pattern that file already uses. Add no other change to that file.

- [ ] **Step 3: Verify**

Run:
```bash
flutter analyze 2>&1 | grep 'error •' || echo "no errors"
flutter test
```
Expected: no analyzer errors, full suite PASSES.

- [ ] **Step 4: Commit**

```bash
git add lib/features/dashboard/authored_stories_section.dart lib/features/dashboard/parent_dashboard_screen.dart
git commit -m "feat(client): manage and delete authored stories from the parent dashboard"
```

---

## Task 11: `HttpTtsClient` multi-file support

**Files:**
- Modify: `lib/features/scan_any_page/tts_client.dart`
- Test: `test/tts_client_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `Future<File> generate(String confirmedText, {String? fileName})` on both `TtsClient` and `HttpTtsClient`.

Today the client writes to a fixed `scan_any_page_narration.mp3` and tracks one file. With a `PageView`, page N+1 can load while page N is still playing, and the second write would clobber the file `just_audio` is reading. The operation queue is strict FIFO (`tts_client.dart:122-124`), so extending the single `_generatedFileOwner` int into a set of `(file, ownerId)` preserves the existing dispose invariant: delete only entries whose `ownerId` is lower than the dispose operation's id.

- [ ] **Step 1: Write the failing test**

Append to `test/tts_client_test.dart`, following the existing fake-Dio setup in that file:

```dart
  test('distinct file names do not clobber each other', () async {
    final client = HttpTtsClient(
      fakeApiClient(audioBytes: [1, 2, 3]),
      temporaryDirectory: () => tempDir,
    );

    final first = await client.generate('page one', fileName: 'narration_a.mp3');
    final second = await client.generate('page two', fileName: 'narration_b.mp3');

    expect(first.path, isNot(second.path));
    expect(await first.exists(), isTrue);
    expect(await second.exists(), isTrue);
  });

  test('dispose deletes every generated file', () async {
    final client = HttpTtsClient(
      fakeApiClient(audioBytes: [1, 2, 3]),
      temporaryDirectory: () => tempDir,
    );

    final first = await client.generate('one', fileName: 'narration_a.mp3');
    final second = await client.generate('two', fileName: 'narration_b.mp3');
    await client.dispose();

    expect(await first.exists(), isFalse);
    expect(await second.exists(), isFalse);
  });

  test('omitting fileName keeps the existing default name', () async {
    final client = HttpTtsClient(
      fakeApiClient(audioBytes: [1, 2, 3]),
      temporaryDirectory: () => tempDir,
    );
    final file = await client.generate('text');
    expect(file.path, endsWith('scan_any_page_narration.mp3'));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tts_client_test.dart`
Expected: FAIL - `generate` does not accept a `fileName` named argument.

- [ ] **Step 3: Widen the interface**

In `lib/features/scan_any_page/tts_client.dart`:

```dart
abstract interface class TtsClient {
  /// Generates narration audio. [fileName] lets a caller keep several clips
  /// alive at once (the player holds one per page); omitting it reuses the
  /// single-clip name the scan-any-page flow has always used.
  Future<File> generate(String confirmedText, {String? fileName});

  Future<void> dispose();
}
```

- [ ] **Step 4: Track a set of files instead of one**

In `HttpTtsClient`, replace the two single-file fields:

```dart
  final Map<String, int> _generatedFileOwners = {};   // absolute path -> operation id
```

Delete `_generatedFileOwner` and `_generatedFile`.

Change `generate` to thread the name through:

```dart
  @override
  Future<File> generate(String confirmedText, {String? fileName}) {
    final text = confirmedText.trim();
    if (text.isEmpty || text.runes.length > 4000) {
      return Future.error(const TtsGenerationFailure('invalid_text'));
    }

    final operationId = ++_nextOperationId;
    final completion = Completer<File>();
    _enqueue(() async {
      try {
        completion.complete(
          await _generate(text, operationId, fileName ?? _fileName),
        );
      } catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
  }
```

In `_generate`, take the name and record the owner:

```dart
  Future<File> _generate(String text, int operationId, String fileName) async {
    // ... the Dio call and validation are unchanged ...
    final directory = _temporaryDirectory();
    final file = File('${directory.path}/$fileName');
    final temporaryFile =
        File('${directory.path}/.$fileName.$operationId.tmp');
    try {
      await temporaryFile.writeAsBytes(bytes, flush: true);
      await temporaryFile.rename(file.path);
      _generatedFileOwners[file.path] = operationId;
      return file;
    } finally {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }
```

And in `dispose`, delete every file created by an earlier operation:

```dart
  @override
  Future<void> dispose() {
    final operationId = ++_nextOperationId;
    final completion = Completer<void>();
    _enqueue(() async {
      try {
        for (final entry in _generatedFileOwners.entries.toList()) {
          if (entry.value >= operationId) continue;
          final file = File(entry.key);
          if (await file.exists()) await file.delete();
        }
        _generatedFileOwners.clear();
        completion.complete();
      } catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
  }
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/tts_client_test.dart test/scan_any_page_controller_test.dart`
Expected: PASS, including the pre-existing "serializes generations" and "dispose waits for in-flight generation" tests.

- [ ] **Step 6: Commit**

```bash
git add lib/features/scan_any_page/tts_client.dart test/tts_client_test.dart
git commit -m "feat(client): let HttpTtsClient hold several named clips at once"
```

---

## Task 12: `NarrationAudioFetcher`

**Files:**
- Create: `lib/features/player/narration_audio_fetcher.dart`
- Test: `test/narration_audio_fetcher_test.dart`

**Interfaces:**
- Consumes: `TtsClient` (Task 11).
- Produces:
  - `abstract interface class NarrationAudioFetcher { Future<String?> pathFor(NarrationSegment segment); Future<void> dispose(); }`
  - `class TtsNarrationAudioFetcher implements NarrationAudioFetcher`

The cache stores **in-flight `Future`s, not finished paths**. Two fetches for the same segment - a page-back before the first resolves - would otherwise rename over the same file while `just_audio` holds it open. The cache dies with the client, because `dispose()` deletes every generated file and a surviving cache would hand back dangling paths.

- [ ] **Step 1: Write the failing test**

Create `test/narration_audio_fetcher_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/features/player/narration_audio_fetcher.dart';
import 'package:storybook_ar/features/scan_any_page/tts_client.dart';

class _FakeTtsClient implements TtsClient {
  _FakeTtsClient({this.failure});

  final TtsGenerationFailure? failure;
  final calls = <String>[];
  final pending = <Completer<File>>[];
  var disposed = false;

  @override
  Future<File> generate(String confirmedText, {String? fileName}) {
    calls.add(fileName ?? 'default');
    if (failure != null) return Future.error(failure!);
    final completer = Completer<File>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

NarrationSegment _segment(String id, String text) => NarrationSegment(
      id: id, storyId: 's', pageId: 'p', speakerKey: 'narrator',
      text: text, voiceId: 'coral', sortOrder: 0,
    );

void main() {
  test('fetches once per segment and caches the result', () async {
    final client = _FakeTtsClient();
    final fetcher = TtsNarrationAudioFetcher(client);

    final first = fetcher.pathFor(_segment('seg1', 'hello'));
    client.pending.single.complete(File('/tmp/seg1.mp3'));
    expect(await first, '/tmp/seg1.mp3');

    expect(await fetcher.pathFor(_segment('seg1', 'hello')), '/tmp/seg1.mp3');
    expect(client.calls, hasLength(1));
  });

  test('a second request while the first is in flight reuses the same future',
      () async {
    final client = _FakeTtsClient();
    final fetcher = TtsNarrationAudioFetcher(client);

    final first = fetcher.pathFor(_segment('seg1', 'hello'));
    final second = fetcher.pathFor(_segment('seg1', 'hello'));
    expect(client.calls, hasLength(1));

    client.pending.single.complete(File('/tmp/seg1.mp3'));
    expect(await first, '/tmp/seg1.mp3');
    expect(await second, '/tmp/seg1.mp3');
  });

  test('returns null on generation failure and does not cache the failure',
      () async {
    final client = _FakeTtsClient(failure: const TtsGenerationFailure('timeout'));
    final fetcher = TtsNarrationAudioFetcher(client);

    expect(await fetcher.pathFor(_segment('seg1', 'hello')), isNull);
    expect(await fetcher.pathFor(_segment('seg1', 'hello')), isNull);
    expect(client.calls, hasLength(2), reason: 'a failure must stay retryable');
  });

  test('uses a distinct file name per segment', () async {
    final client = _FakeTtsClient();
    final fetcher = TtsNarrationAudioFetcher(client);

    fetcher.pathFor(_segment('seg1', 'a'));
    fetcher.pathFor(_segment('seg2', 'b'));

    expect(client.calls.toSet(), hasLength(2));
  });

  test('dispose clears the cache and disposes the client', () async {
    final client = _FakeTtsClient();
    final fetcher = TtsNarrationAudioFetcher(client);

    final first = fetcher.pathFor(_segment('seg1', 'a'));
    client.pending.single.complete(File('/tmp/seg1.mp3'));
    await first;
    await fetcher.dispose();

    expect(client.disposed, isTrue);
    fetcher.pathFor(_segment('seg1', 'a'));
    expect(client.calls, hasLength(2), reason: 'cache must not survive dispose');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/narration_audio_fetcher_test.dart`
Expected: FAIL - `narration_audio_fetcher.dart` does not exist.

- [ ] **Step 3: Write the fetcher**

Create `lib/features/player/narration_audio_fetcher.dart`:

```dart
import 'dart:async';

import '../../data/models/models.dart';
import '../scan_any_page/tts_client.dart';

/// Supplies a locally cached narration clip for a segment that has no
/// pre-generated `audio_asset_id`. Returns null when generation fails, which
/// the player treats as "fall back to on-device TTS".
abstract interface class NarrationAudioFetcher {
  Future<String?> pathFor(NarrationSegment segment);

  Future<void> dispose();
}

/// Backed by the authenticated OpenAI proxy (`POST /v1/tts`).
///
/// Caches the in-flight [Future], not the finished path: two requests for the
/// same segment (page-back before the first resolves) must not both write to
/// the same file while just_audio holds it open. Failures are not cached, so a
/// dropped connection stays retryable on the next page turn.
class TtsNarrationAudioFetcher implements NarrationAudioFetcher {
  TtsNarrationAudioFetcher(this._client);

  final TtsClient _client;
  final Map<String, Future<String?>> _cache = {};

  @override
  Future<String?> pathFor(NarrationSegment segment) {
    final cached = _cache[segment.id];
    if (cached != null) return cached;

    final pending = _generate(segment);
    _cache[segment.id] = pending;
    return pending;
  }

  Future<String?> _generate(NarrationSegment segment) async {
    try {
      final file = await _client.generate(
        segment.text,
        fileName: 'narration_${segment.id}.mp3',
      );
      return file.path;
    } catch (_) {
      // Keep it retryable: a failed fetch must not poison the cache.
      _cache.remove(segment.id);
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    // dispose() deletes every generated file, so the cache must not outlive it.
    _cache.clear();
    await _client.dispose();
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/narration_audio_fetcher_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/player/narration_audio_fetcher.dart test/narration_audio_fetcher_test.dart
git commit -m "feat(client): add NarrationAudioFetcher with in-flight caching"
```

---

## Task 13: Third audio source in `NarrationPlayer`

**Files:**
- Modify: `lib/features/player/narration_player.dart`
- Test: `test/narration_player_test.dart`

**Interfaces:**
- Consumes: `NarrationAudioFetcher` (Task 12).
- Produces: `NarrationPlayer({AudioPlayer? filePlayer, FlutterTts? tts, AssetUrlResolver? resolver, NarrationAudioFetcher? fetcher})`; `static bool computeTtsFallback(List<NarrationSegment> segments, Map<String, String> urls, Map<String, String> fetched)`.

Precedence becomes: **signed asset clip -> fetched OpenAI clip -> on-device TTS**. When `fetcher` is null the behaviour is byte-for-byte what it is today.

- [ ] **Step 1: Write the failing test**

Append to `test/narration_player_test.dart`:

```dart
  group('computeTtsFallback with fetched clips', () {
    final segment = NarrationSegment(
      id: 'seg1', storyId: 's', pageId: 'p', speakerKey: 'narrator',
      text: 'hello', voiceId: 'coral', sortOrder: 0,
    );

    test('is false when a fetched clip covers the segment', () {
      expect(
        NarrationPlayer.computeTtsFallback(
          [segment], const {}, const {'seg1': '/tmp/seg1.mp3'},
        ),
        isFalse,
      );
    });

    test('is true when neither an asset nor a fetched clip covers it', () {
      expect(
        NarrationPlayer.computeTtsFallback([segment], const {}, const {}),
        isTrue,
      );
    });

    test('is false when a signed asset covers it', () {
      final withAsset = segment.copyWith(audioAssetId: 'aud_1');
      expect(
        NarrationPlayer.computeTtsFallback(
          [withAsset], const {'aud_1': 'https://x/clip'}, const {},
        ),
        isFalse,
      );
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/narration_player_test.dart`
Expected: FAIL - `computeTtsFallback` takes 2 positional arguments, not 3.

- [ ] **Step 3: Add the fetcher and the fetched map**

In `lib/features/player/narration_player.dart`:

```dart
  NarrationPlayer({
    AudioPlayer? filePlayer,
    FlutterTts? tts,
    AssetUrlResolver? resolver,
    NarrationAudioFetcher? fetcher,
  })  : _file = filePlayer ?? AudioPlayer(),
        _tts = tts ?? FlutterTts(),
        _resolver = resolver,
        _fetcher = fetcher;

  final NarrationAudioFetcher? _fetcher;

  /// Locally generated clips for the current page, keyed by segment id.
  Map<String, String> _pathBySegmentId = {};
```

Update the doc comment on the class to describe the three-source strategy rather than two.

- [ ] **Step 4: Update `computeTtsFallback`**

```dart
  /// True when at least one segment can play from neither a registered clip
  /// nor a locally fetched one, and must therefore use on-device TTS.
  static bool computeTtsFallback(
    List<NarrationSegment> segments,
    Map<String, String> urls,
    Map<String, String> fetched,
  ) =>
      segments.any((s) =>
          !(s.hasAudioAsset && urls.containsKey(s.audioAssetId)) &&
          !fetched.containsKey(s.id));
```

- [ ] **Step 5: Fetch in `load()`**

In `load()`, after the existing `_urlByAssetId` assignment and before `usingTtsFallback` is set:

```dart
    final fetcher = _fetcher;
    final fetched = <String, String>{};
    if (fetcher != null) {
      for (final segment in segments) {
        if (segment.hasAudioAsset &&
            _urlByAssetId.containsKey(segment.audioAssetId)) {
          continue;
        }
        final path = await fetcher.pathFor(segment);
        if (path != null) fetched[segment.id] = path;
      }
    }
    _pathBySegmentId = fetched;
    usingTtsFallback.value =
        computeTtsFallback(segments, _urlByAssetId, _pathBySegmentId);
```

Task 14 adds the staleness guard around these awaits. Do not ship this task without it.

- [ ] **Step 6: Add the branch to `_playSegment`**

Replace the body of `_playSegment` after the `speed` line:

```dart
    final url = seg.hasAudioAsset ? _urlByAssetId[seg.audioAssetId] : null;
    final path = _pathBySegmentId[seg.id];

    if (url != null || path != null) {
      try {
        if (url != null) {
          await _file.setUrl(url);
        } else {
          await _file.setFilePath(path!);
        }
        await _file.setSpeed(speed);
        final done = _file.processingStateStream
            .firstWhere((s) => s == ProcessingState.completed);
        unawaited(_file.play());
        await Future.any([done, interrupt]);
        return;
      } catch (_) {
        // A missing or corrupt clip must not leave the page silent: with one
        // segment per page, skipping here means no narration at all and, on the
        // last page, an instant completion dialog. Fall through to device TTS.
      }
    }

    await _ensureTts();
    await _tts.setSpeechRate(_ttsRate(speed));
    await _tts.setPitch(_pitchFor(seg.speakerKey));
    // awaitSpeakCompletion(true) makes speak() resolve when finished/stopped.
    await Future.any([_tts.speak(seg.text), interrupt]);
```

Note the `return` on the success path and the fall-through on failure. This is the fix for the silent-page bug: today the catch swallows the error and the segment is skipped entirely.

- [ ] **Step 7: Dispose the fetcher**

In `dispose()`, before `await _file.dispose();`:

```dart
    await _fetcher?.dispose();
```

- [ ] **Step 8: Run tests and analyze**

Run:
```bash
flutter test test/narration_player_test.dart
flutter analyze 2>&1 | grep 'error •' || echo "no errors"
```
Expected: PASS, no errors.

- [ ] **Step 9: Commit**

```bash
git add lib/features/player/narration_player.dart test/narration_player_test.dart
git commit -m "feat(client): add fetched-clip audio source to NarrationPlayer"
```

---

## Task 14: Staleness guards in `load()` and `_loadPage`

**Files:**
- Modify: `lib/features/player/narration_player.dart`
- Modify: `lib/features/player/story_player_screen.dart:92-115`
- Test: `test/narration_player_test.dart`

**Interfaces:**
- Consumes: Task 13's `load()`.
- Produces: `NarrationPlayer.isLoading` (`ValueNotifier<bool>`), consumed by the player UI.

`load()` has **no staleness protection today**: it awaits `_resolver.resolve()` and then unconditionally writes `_urlByAssetId` and `usingTtsFallback` (`narration_player.dart:66-87`). `_onPageChanged` fires `_loadPage` fire-and-forget (`story_player_screen.dart:112-115`) and `_loadPage` continues after its await into `updateLastPage`, `recordEvent` and `play()` (`:98-109`).

Today the awaited step is fast URL signing. Task 13 puts a multi-second OpenAI fetch in exactly that spot. Without this task: `load(N)` in flight -> swipe to `N+1` -> `load(N+1)` resets `_segments` -> `load(N)` resolves, overwrites the clip map with page-N data, regresses `last_page_number` to N, and starts playback of page N+1 using page N's map.

- [ ] **Step 1: Write the failing test**

Append to `test/narration_player_test.dart`. Use a fake `AssetUrlResolver` and a fake `NarrationAudioFetcher` whose completion you control:

```dart
  test('a stale load does not overwrite a newer page state', () async {
    final slowFetcher = _ControllableFetcher();
    // Reuse whatever AudioPlayer/FlutterTts fakes this file already defines for
    // its existing tests; if it has none, write minimal ones that record calls
    // and complete immediately.
    final player = NarrationPlayer(
      filePlayer: fakeAudioPlayer(),
      tts: fakeTts(),
      fetcher: slowFetcher,
    );

    final pageOne = [
      NarrationSegment(id: 'a', storyId: 's', pageId: 'p1',
          speakerKey: 'narrator', text: 'one', voiceId: 'coral', sortOrder: 0),
    ];
    final pageTwo = [
      NarrationSegment(id: 'b', storyId: 's', pageId: 'p2',
          speakerKey: 'narrator', text: 'two', voiceId: 'coral', sortOrder: 0),
    ];

    final staleLoad = player.load(pageOne);        // in flight
    await player.load(pageTwo);                    // newer page wins
    slowFetcher.complete('a', '/tmp/a.mp3');       // stale fetch resolves late
    await staleLoad;

    expect(player.debugFetchedPaths.containsKey('a'), isFalse,
        reason: 'the stale load must not write into the current page state');
  });
```

Add a debug-only accessor to the player for the assertion:

```dart
  @visibleForTesting
  Map<String, String> get debugFetchedPaths => _pathBySegmentId;
```

Write `_ControllableFetcher` in the test file as a `NarrationAudioFetcher` holding a `Map<String, Completer<String?>>`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/narration_player_test.dart -N "stale load"`
Expected: FAIL - the stale load writes `a` into `_pathBySegmentId`.

- [ ] **Step 3: Guard `load()`**

In `NarrationPlayer`, add a counter and a public loading flag:

```dart
  var _loadGeneration = 0;

  /// True while a page's audio is being resolved or fetched. The player UI
  /// disables playback controls on this, so a tap during a multi-second TTS
  /// fetch cannot start device TTS a moment before the clip lands.
  final ValueNotifier<bool> isLoading = ValueNotifier(false);
```

Rewrite `load()` so **every** await is followed by a generation check before any field write:

```dart
  Future<void> load(
    List<NarrationSegment> segments, {
    double speedMultiplier = 1.0,
    String languageCode = 'en',
  }) async {
    final generation = ++_loadGeneration;
    await _haltLoop();
    if (generation != _loadGeneration) return;

    _segments = segments;
    _speedMultiplier = speedMultiplier;
    _languageCode = languageCode;
    _cursor = 0;
    currentSegmentIndex.value = -1;
    isComplete.value = false;
    isLoading.value = true;

    try {
      final ids = segments
          .where((s) => s.hasAudioAsset)
          .map((s) => s.audioAssetId!)
          .toList();
      final urls = (_resolver != null && ids.isNotEmpty)
          ? await _resolver!.resolve(ids)
          : <String, String>{};
      if (generation != _loadGeneration) return;

      final fetcher = _fetcher;
      final fetched = <String, String>{};
      if (fetcher != null) {
        for (final segment in segments) {
          if (segment.hasAudioAsset && urls.containsKey(segment.audioAssetId)) {
            continue;
          }
          final path = await fetcher.pathFor(segment);
          if (generation != _loadGeneration) return;
          if (path != null) fetched[segment.id] = path;
        }
      }

      _urlByAssetId = urls;
      _pathBySegmentId = fetched;
      usingTtsFallback.value =
          computeTtsFallback(segments, _urlByAssetId, _pathBySegmentId);
    } finally {
      if (generation == _loadGeneration) isLoading.value = false;
    }
  }
```

Dispose `isLoading` alongside the other notifiers in `dispose()`.

- [ ] **Step 4: Guard `_loadPage`**

In `lib/features/player/story_player_screen.dart`, add a field and check it after the await. The session write and the `play()` call are as stale as the audio map:

```dart
  int _loadGeneration = 0;

  Future<void> _loadPage(int index, {required bool autoplay}) async {
    final generation = ++_loadGeneration;
    final page = _pages[index];
    await _player.load(
      widget.detail.segmentsForPage(page.id),
      speedMultiplier: _effectiveSpeed(),
      languageCode: _story.languageCode,
    );
    if (!mounted || generation != _loadGeneration) return;

    final sid = _sessionId;
    if (sid != null) {
      final repo = ref.read(sessionRepositoryProvider);
      await repo.updateLastPage(sid, page.pageNumber);
      if (!mounted || generation != _loadGeneration) return;
      await repo.recordEvent(
        sessionId: sid,
        eventType: 'page_viewed',
        pageId: page.id,
        payload: {'page_number': page.pageNumber},
      );
      if (!mounted || generation != _loadGeneration) return;
    }
    if (autoplay) await _player.play();
  }
```

- [ ] **Step 5: Disable playback controls while loading**

Wrap the play control in a `ValueListenableBuilder` on `_player.isLoading` and pass `onPressed: null` while it is true. Locate the play button via the `_player.isPlaying` listener already in the file and follow the same pattern.

- [ ] **Step 6: Run tests and analyze**

Run:
```bash
flutter test
flutter analyze 2>&1 | grep 'error •' || echo "no errors"
```
Expected: full suite PASSES, no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/features/player/narration_player.dart lib/features/player/story_player_screen.dart test/narration_player_test.dart
git commit -m "fix(client): guard NarrationPlayer.load and _loadPage against stale page turns"
```

---

## Task 15: Engage the fetcher for authored stories only

**Files:**
- Modify: `lib/features/player/story_player_screen.dart:64`
- Modify: `lib/core/di.dart`

**Interfaces:**
- Consumes: `Story.isAuthored` (Task 6), `TtsNarrationAudioFetcher` (Task 12), `NarrationPlayer` fetcher argument (Task 13).
- Produces: nothing consumed by later tasks.

Without this gate, any environment where `register_assets.py` has not run would silently convert curated pages into one OpenAI call each.

- [ ] **Step 1: Add a fetcher provider**

In `lib/core/di.dart`:

```dart
/// Per-story narration fetcher for authored stories. autoDispose so the
/// underlying TtsClient - and every temp clip it wrote - is torn down when the
/// player leaves.
final narrationAudioFetcherProvider =
    Provider.autoDispose.family<NarrationAudioFetcher, String>((ref, storyId) {
  final fetcher = TtsNarrationAudioFetcher(
    HttpTtsClient(
      ref.watch(apiClientProvider),
      temporaryDirectory: ref.watch(ttsTemporaryDirectoryProvider),
    ),
  );
  ref.onDispose(() => fetcher.dispose());
  return fetcher;
});
```

- [ ] **Step 2: Gate the construction**

In `lib/features/player/story_player_screen.dart`, replace line 64:

```dart
    _player = NarrationPlayer(
      resolver: ref.read(assetUrlResolverProvider),
      // Curated stories play registered clips or the device-TTS fallback.
      // Only authored stories generate narration per read.
      fetcher: widget.detail.story.isAuthored
          ? ref.read(narrationAudioFetcherProvider(widget.detail.story.id))
          : null,
    );
```

Because the provider is `autoDispose` and `NarrationPlayer.dispose()` also calls `_fetcher?.dispose()`, confirm `TtsNarrationAudioFetcher.dispose()` is safe to call twice - `_cache.clear()` and `TtsClient.dispose()` both are.

- [ ] **Step 3: Verify**

Run:
```bash
flutter test
flutter analyze 2>&1 | grep 'error •' || echo "no errors"
```
Expected: full suite PASSES, no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/core/di.dart lib/features/player/story_player_screen.dart
git commit -m "feat(client): use the narration fetcher for authored stories only"
```

---

## Task 16: Promote the Android ML Kit scanner to release

**Files:**
- Move: `android/app/src/debug/kotlin/com/storybookar/storybook_ar/scananypage/{ScanAnyPageBridge,ReadingOrderSorter,ScannerFailureMapper}.kt` -> `src/main/kotlin/com/storybookar/storybook_ar/scananypage/`
- Move: `android/app/src/debug/kotlin/com/storybookar/storybook_ar/OneShotGate.kt` -> `src/main/kotlin/com/storybookar/storybook_ar/`
- Create: `android/app/src/main/kotlin/com/storybookar/storybook_ar/ScanAnyPageRequestCodes.kt`
- Modify: `android/app/src/debug/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt`
- Modify: `android/app/src/release/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt`
- Modify: `android/app/src/profile/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt`
- Modify: `android/app/build.gradle.kts:57-58`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `ScanAnyPageBridges.register(activity, messenger)` registering the scanner on every variant.

**No manifest change.** `android.permission.CAMERA` is already in `src/main/AndroidManifest.xml:6`; only the ARCore half - `camera.ar` `uses-feature`, `com.google.ar.core` meta-data, `CharacterReaderActivity` - lives in `src/debug/AndroidManifest.xml`, and it stays there.

- [ ] **Step 1: Move the scanner sources**

```bash
cd android/app/src
mkdir -p main/kotlin/com/storybookar/storybook_ar/scananypage
git mv debug/kotlin/com/storybookar/storybook_ar/scananypage/ScanAnyPageBridge.kt main/kotlin/com/storybookar/storybook_ar/scananypage/
git mv debug/kotlin/com/storybookar/storybook_ar/scananypage/ReadingOrderSorter.kt main/kotlin/com/storybookar/storybook_ar/scananypage/
git mv debug/kotlin/com/storybookar/storybook_ar/scananypage/ScannerFailureMapper.kt main/kotlin/com/storybookar/storybook_ar/scananypage/
git mv debug/kotlin/com/storybookar/storybook_ar/OneShotGate.kt main/kotlin/com/storybookar/storybook_ar/
```

Package declarations do not change - only the source set does.

- [ ] **Step 2: Extract the shared request code**

`SCANNER_REQUEST_CODE` currently lives only in the debug `ScanAnyPageBridges` companion, and the release and profile copies now need it. Create `android/app/src/main/kotlin/com/storybookar/storybook_ar/ScanAnyPageRequestCodes.kt`:

```kotlin
package com.storybookar.storybook_ar

/** Shared by every build variant; the reader's code stays debug-only. */
internal const val SCANNER_REQUEST_CODE = 0x51A1
```

- [ ] **Step 3: Rewrite the release and profile bridges**

Put this identical body in **both** `src/release/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt` and `src/profile/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt`:

```kotlin
package com.storybookar.storybook_ar

import android.app.Activity
import android.content.Intent
import com.storybookar.storybook_ar.scananypage.ScanAnyPageBridge
import io.flutter.plugin.common.BinaryMessenger

/**
 * Release/profile registers the ML Kit scanner only. The ARCore character
 * reader stays debug-only, which is what keeps AR entries out of the release
 * manifest.
 */
class ScanAnyPageBridges private constructor(
    private val scanner: ScanAnyPageBridge,
) {
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        scanner.onActivityResult(requestCode, resultCode, data)
    }

    // Only the ARCore reader needs a resume signal (ArCoreApk.requestInstall()
    // reports back on resume), so this is a no-op outside debug.
    fun onHostResume() = Unit

    companion object {
        fun register(activity: Activity, messenger: BinaryMessenger): ScanAnyPageBridges =
            ScanAnyPageBridges(
                scanner = ScanAnyPageBridge(
                    activity = activity,
                    messenger = messenger,
                    requestCode = SCANNER_REQUEST_CODE,
                ),
            )
    }
}
```

- [ ] **Step 4: Update the debug bridge**

In `src/debug/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt`, delete `SCANNER_REQUEST_CODE` from the companion (it now comes from `main`) and keep `READER_REQUEST_CODE` there. Everything else in that file stays.

- [ ] **Step 5: Promote the ML Kit dependencies**

In `android/app/build.gradle.kts`, change only these two lines:

```kotlin
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    implementation("com.google.mlkit:text-recognition:16.0.1")
```

`com.google.ar:core`, `io.github.sceneview:arsceneview`, `androidx.activity:activity-compose`, and every `androidx.compose.*` line stay `debugImplementation`. Leave the `compileOnly` Compose block and its comment untouched - it still holds, because no `main` source references a `@Composable`.

- [ ] **Step 6: Compile every variant**

Run:
```bash
flutter build apk --debug
flutter build apk --release
flutter build apk --profile
```
Expected: all three succeed. A failure mentioning `arsceneview` or `kotlin-stdlib 2.4` means an AR dependency leaked into a non-debug source set - re-check step 5.

- [ ] **Step 7: Verify the release manifest has no AR entries**

Run:
```bash
grep -E "com\.google\.ar\.core|camera\.ar|CharacterReaderActivity" \
  android/app/build/intermediates/merged_manifests/release/AndroidManifest.xml \
  || echo "clean: no AR entries in the release manifest"
```
Expected: prints `clean: ...`. If the path differs in this Gradle version, locate the merged release manifest under `android/app/build/intermediates/` and grep that.

- [ ] **Step 8: Commit**

```bash
git add android/app/src android/app/build.gradle.kts
git commit -m "feat(android): ship the ML Kit page scanner in release builds"
```

---

## Task 17: Relocate the Android scanner tests

**Files:**
- Move: `android/app/src/testDebug/kotlin/com/storybookar/storybook_ar/scananypage/ReadingOrderSorterTest.kt` -> `src/test/kotlin/...`
- Move: `android/app/src/testDebug/kotlin/com/storybookar/storybook_ar/OneShotGateTest.kt` -> `src/test/kotlin/...`
- Create: `android/app/src/test/kotlin/com/storybookar/storybook_ar/ScannerFailureMappingTest.kt`
- Modify: `android/app/src/testDebug/kotlin/com/storybookar/storybook_ar/NativeFailureMappingTest.kt`

**Interfaces:**
- Consumes: Task 16's source layout.
- Produces: nothing consumed by later tasks.

Code that now ships in release must be covered by the default `test` task, not only `testDebug`.

- [ ] **Step 1: Move the two variant-agnostic tests**

```bash
cd android/app/src
mkdir -p test/kotlin/com/storybookar/storybook_ar/scananypage
git mv testDebug/kotlin/com/storybookar/storybook_ar/scananypage/ReadingOrderSorterTest.kt test/kotlin/com/storybookar/storybook_ar/scananypage/
git mv testDebug/kotlin/com/storybookar/storybook_ar/OneShotGateTest.kt test/kotlin/com/storybookar/storybook_ar/
```

- [ ] **Step 2: Split `NativeFailureMappingTest`**

`NativeFailureMappingTest` mixes `ScannerFailureMapper` assertions with ARCore `CharacterReader` ones in one file. Create `android/app/src/test/kotlin/com/storybookar/storybook_ar/ScannerFailureMappingTest.kt` containing **only** the `ScannerFailureMapper` test methods, moved verbatim from `NativeFailureMappingTest` along with the imports they need (`android.app.Activity`, `com.storybookar.storybook_ar.scananypage.ScannerFailureMapper`, the JUnit asserts).

Then delete those methods and the now-unused `ScannerFailureMapper` import from the `testDebug` copy, leaving it with only the `ArCoreAvailabilityMapper`, `ArCoreInstallPolicy` and `CharacterReaderResultMapper` cases.

- [ ] **Step 3: Run both test tasks**

Run:
```bash
cd android && ./gradlew test
```
Expected: BUILD SUCCESSFUL. Confirm in the output that both `testDebugUnitTest` and `testReleaseUnitTest` ran, and that the scanner cases appear under the release task.

- [ ] **Step 4: Commit**

```bash
git add android/app/src
git commit -m "test(android): cover the promoted scanner in the default test source set"
```

---

## Task 18: Full verification

**Files:** none modified.

**Interfaces:**
- Consumes: every prior task.
- Produces: a green build.

- [ ] **Step 1: Backend**

```bash
cd backend && uv run alembic upgrade head && uv run pytest tests/ -v
```
Expected: migration applies cleanly, every test PASSES.

- [ ] **Step 2: Dart**

```bash
flutter analyze
flutter test
```
Expected: only the pre-existing `narration_player.dart:84` `unnecessary_non_null_assertion` warning; every test PASSES.

- [ ] **Step 3: Android JVM tests and all three variants**

```bash
cd android && ./gradlew test
cd .. && flutter build apk --debug && flutter build apk --release && flutter build apk --profile
```
Expected: all green.

- [ ] **Step 4: Release manifest gate**

```bash
grep -E "com\.google\.ar\.core|camera\.ar|CharacterReaderActivity" \
  android/app/build/intermediates/merged_manifests/release/AndroidManifest.xml \
  || echo "clean: no AR entries in the release manifest"
```
Expected: `clean: ...`.

- [ ] **Step 5: iOS builds**

```bash
flutter build ios --debug --no-codesign
flutter build ios --release --no-codesign
```
Expected: both succeed.

- [ ] **Step 6: Physical-device acceptance**

With the backend running and reachable, on a real device:

1. Tap "Create story" in the library app bar.
2. Scan three pages; correct the text on one of them.
3. Name the story and save. Confirm it appears in the library with a non-zero duration.
4. Open it. Confirm each page is narrated in the OpenAI voice, not the device voice, and that the fallback banner does **not** appear.
5. Page back and forth. Confirm no audio crossover between pages and no visible refetch delay on a page already visited.
6. Turn off the network and open the story again. Confirm it still reads, in the device voice, with the banner shown.
7. Go to the grown-ups area, delete the story, and confirm it disappears from the library and 404s if reopened.

- [ ] **Step 7: Final commit**

```bash
git add -A
git commit -m "chore: capture-to-story verification pass"
```
