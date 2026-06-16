# Backend API — Client-Contract Slice (design)

**Date:** 2026-06-17
**Status:** Draft for review
**Slice:** Platform slice 2 of N. Slice 1 (Flutter MVP-lite client) is built and
committed. This slice gives that client a real backend to talk to.
**Source spec:** `interactive_storybook_voice_ar_product_technical_spec.md`
(§9 architecture, §10 data model, §11 API, §14 privacy, §15 security, §18 infra).

---

## 1. Goal

Stand up the backend the existing Flutter client already implies, and switch the
client from bundled-local content to HTTP — with **no UI rework**. After this
slice, the running app fetches its library, story detail, child profiles, and
records sessions/events against a Python/FastAPI service backed by Postgres.

## 2. Locked decisions (from brainstorming)

| Decision | Choice |
|----------|--------|
| Breadth | **Client-contract slice** — only the endpoints the client consumes |
| Language/framework | **Python + FastAPI** (Pydantic v2) |
| Auth | **Anonymous device account** — device id → provisioned `users` row → JWT |
| Client swap | **Included** — Flutter repos rewritten to HTTP in this slice |

## 3. Non-goals (explicitly deferred to later slices)

Entitlements / activation codes · admin & content-studio endpoints · audio/AR
asset serving + signed URLs · Redis caching · CDN · the 6 async workers ·
image-target manifest endpoint · **real parent auth** (passwordless/OAuth,
account recovery, multi-device sync) · offline caching/sync (§7.1.7) ·
classroom mode · localization.

---

## 4. Contract source of truth — a deliberate divergence

The spec's §11 JSON examples (`age_range`, `cover_url`, …) are **illustrative and
diverge** from the client's actual serialized models (`age_min`/`age_max`,
`cover_asset_id`, snake_case throughout). Per the data-model-fidelity rule, **the
API mirrors the client's real shape — which is exactly the bundled
`assets/data/*.json` files**, already locked by `test/content_parsing_test.dart`.

Consequence: the 5 bundled JSON files double as the **seed data**, and a contract
test asserts `GET /v1/stories/{id}` reproduces them byte-equivalent (modulo key
ordering). The client's freezed `fromJson` is the acceptance oracle.

---

## 5. Data model

### 5.1 §10 tables, used verbatim

`users`, `child_profiles`, `stories`, `story_pages`, `narration_segments`,
`ar_scenes`, `story_sessions`, `interaction_events` — column-for-column as §10.
`ar_scenes.scene_json` stays `JSONB` (unchanged shape, see the bundled AR scene).

### 5.2 Extensions beyond §10 (with rationale)

These are **additive** — the §10 tables are not modified.

- **`devices`** — `(device_id TEXT UNIQUE, user_id UUID FK→users, created_at)`.
  Maps an anonymous device to its provisioned parent `users` row, keeping
  `users` itself §10-pure (`email` null, `auth_provider = 'device'`). Avoids
  bolting a `device_id` column onto the spec's `users` table.
- **`questions`** — `(id UUID, story_id FK, page_id FK, type TEXT, prompt TEXT,
  sort_order INT)`. **§10 omits a questions table**, but §7.1.5 and the content
  require one; modeled on the client's `Question` DTO.
- **`question_choices`** — `(id UUID, question_id FK, label TEXT, emoji TEXT,
  is_correct BOOL, sort_order INT)`. Modeled on the client's `AnswerChoice`.
  `sort_order` preserves the JSON array order the client renders.

### 5.3 Asset-id fields are TEXT in this slice

§10 types `cover_asset_id` / `page_image_asset_id` / `audio_asset_id` as `UUID`
referencing an assets table. No assets table or real assets exist yet (asset
service is deferred), and the client models them as `String?` holding placeholder
paths (`assets/images/covers/…`). **This slice stores them as `TEXT`** and returns
the same placeholder paths the client already tolerates. The proper assets table +
signed-URL serving arrives with the asset slice.

### 5.4 Migrations & seed

SQLAlchemy 2.0 ORM models + **Alembic** migrations create the schema. A
`seed.py` ingests `assets/data/manifest.json` + the 5 detail files into Postgres,
so API output == what the client already parses.

---

## 6. API surface

All paths are `/v1/*`. All except `POST /v1/auth/device` require
`Authorization: Bearer <jwt>`. `child_profiles` and `story_sessions` are scoped
to the JWT's `user_id`; cross-user access returns `404` (not `403`, to avoid
leaking existence).

| Method | Path | Backs (client) | Notes |
|--------|------|----------------|-------|
| `POST` | `/v1/auth/device` | bootstrap | body `{device_id}` → `{token, user_id}`; upsert device+user |
| `GET` | `/v1/child-profiles` | `ProfileRepository.getProfile` | list for the user |
| `POST` | `/v1/child-profiles` | `ProfileRepository.saveProfile` (create) | server sets `user_id` |
| `PATCH` | `/v1/child-profiles/{id}` | `saveProfile` (update) | settings/permission edits |
| `GET` | `/v1/stories?age_band=&language=` | `StoryRepository.getLibrary` | → `{"stories":[Story…]}` |
| `GET` | `/v1/stories/{id}` | `StoryRepository.getStory` | → full `StoryDetail`; `404` if unknown |
| `POST` | `/v1/story-sessions` | `SessionRepository.startSession` | also inserts a `story_started` event |
| `PATCH` | `/v1/story-sessions/{id}` | `updateLastPage` + `completeSession` | sets `last_page_number` / `completed_at`; setting `completed_at` inserts `story_completed` |
| `POST` | `/v1/story-sessions/{id}/events` | `recordEvent` | body `{event_type, page_id?, payload}` |
| `GET` | `/v1/story-sessions?child_profile_id=` | `getSessions` | dashboard aggregation |
| `GET` | `/v1/story-sessions/{id}/events` | `getEvents` | dashboard aggregation |

**Derived endpoints (not in §11):** `PATCH /story-sessions/{id}` and the two
`GET` reads aren't in the spec — they're required by what the player and parent
dashboard already call locally. Documented here as intentional additions.

**Server-side event parity:** the client's `LocalSessionRepository` auto-records
`story_started` on create and `story_completed` on completion. The backend
mirrors this so event analytics match regardless of which repo ran.

### 6.1 Key payload shapes (exact wire shape)

- **Story** (library item and `StoryDetail.story`): `id, title, slug, description,
  age_min, age_max, language_code, duration_seconds, cover_asset_id,
  content_status, rights_owner_id, themes[], is_downloaded, is_unlocked`.
  Server returns `is_unlocked=true` for all demo content (entitlements deferred)
  and `is_downloaded=false` (client owns download state).
- **StoryDetail**: `{story, pages[], segments[], ar_scenes[], questions[]}`.
- **child_profiles**: `id, user_id, nickname, age_band ('3-4'|'5-6'|'7-8'),
  language_code, bedtime_mode_default, microphone_enabled, ar_enabled`.
- **story_sessions**: `id, child_profile_id, story_id, started_at, completed_at,
  last_page_number, mode ('library'|'scan'|'bedtime'|'classroom')`.
- **interaction_events**: `id, story_session_id, event_type, page_id, payload,
  created_at`.

Enum wire values are taken verbatim from `lib/data/models/enums.dart`.

---

## 7. Auth model (anonymous device)

1. On first launch the client generates a UUID `device_id`, persists it in the
   `KeyValueStore`.
2. Client `POST /v1/auth/device {device_id}`. Backend upserts `devices` +
   `users` (one user per device), returns a signed **JWT** (HS256, secret from
   env; `sub = user_id`).
3. Client stores the JWT and sends it as `Authorization: Bearer`. A `dio`
   interceptor re-runs step 2 on `401`/missing token.
4. The client's current `ChildProfile.userId` default (`'local-parent'`) is
   replaced by the server-issued `user_id`.

No email, no PII, no child login → honors §14 (data minimization) and §9.5.1
(no independent child login). Token expiry is long-lived for this slice; refresh
+ rotation come with real parent auth.

---

## 8. Backend architecture

- **Stack:** FastAPI · Pydantic v2 (response models mirror the freezed DTOs) ·
  SQLAlchemy 2.0 + Alembic · Postgres · `uv` for dependency management.
- **Layout** (`backend/`, Flutter app stays at repo root):
  ```
  backend/
    app/
      main.py            # FastAPI app + router registration
      config.py          # env settings (DB url, JWT secret, base path)
      db.py              # engine, session dependency
      auth.py            # device JWT issue/verify, get_current_user dep
      models/            # SQLAlchemy ORM (§10 + extensions)
      schemas/           # Pydantic request/response DTOs
      repositories/      # data access (mirrors the client's repo seam)
      routers/           # stories, child_profiles, sessions, auth
    migrations/          # Alembic
    seed.py              # ingest assets/data/*.json
    tests/
    docker-compose.yml   # local Postgres
    pyproject.toml
  ```
- Layered (routers → repositories → ORM); Pydantic at the edges. Hexagonal/DDD
  considered and rejected as over-engineering for this scope.

---

## 9. Client-side changes (the HTTP swap)

The repository **interfaces are unchanged**; only implementations are added and
the DI wiring is overridden. No widget/UI changes.

- **New dep:** `dio` (interceptors make device-auth + 401-retry clean). *Adds a
  dependency — flagged for review.*
- **`lib/data/sources/api_client.dart`** — `dio` instance, base-URL from config,
  auth interceptor (injects Bearer, bootstraps device on 401).
- **`HttpStoryRepository`, `HttpProfileRepository`, `HttpSessionRepository`** —
  implement the existing abstract interfaces, parse the same JSON the local impls
  produced (freezed `fromJson` reused as-is).
- **`lib/core/di.dart`** — repository providers switch from `Local*` to `Http*`.
  Base URL comes from a compile-time/env config (`--dart-define=API_BASE_URL=…`),
  defaulting to `http://localhost:8000` for dev.
- **Stays local (out of scope for the swap):** `SettingsRepository`
  (voice speed, SFX/music volume — pure app-local UI prefs not in §10).
  Profile-backed fields (`bedtime_mode_default`, `microphone_enabled`,
  `ar_enabled`, `language_code`) sync via `child-profiles`.
- **Connectivity:** HTTP-first. If the backend is unreachable the existing
  `AsyncValue` error views surface it. Offline caching/fallback is a deferred
  feature (§7.1.7), not added here.

---

## 10. Testing & verification gates

**Backend (`pytest` + httpx, transactional test DB):**
- Every endpoint: happy path + validation errors.
- Device-auth scoping: device A cannot read device B's profiles/sessions (`404`).
- **Contract test:** `GET /v1/stories/{id}` for all 5 seeded stories reproduces
  the bundled JSON (same structure/values the client's `content_parsing_test`
  asserts).
- Event parity: `POST /story-sessions` yields a `story_started` event; completing
  yields `story_completed`.

**Client:**
- `flutter analyze` clean.
- Existing `content_parsing_test.dart` still passes (JSON shape unchanged).
- Unit tests for the `Http*` repositories against a **mocked `dio` transport**
  (fast; no real network, no widget/integration tests per project rules).

**End-to-end (manual, optional):** `docker compose up` + run the app with
`--dart-define=API_BASE_URL=…`. Not part of the automated gate; `flutter run`
only on explicit request.

---

## 11. Risks & open questions

| Risk / question | Handling |
|-----------------|----------|
| §10 lacks a questions table | Added `questions` + `question_choices` (§5.2), flagged |
| Asset-id type drift (UUID vs TEXT) | Stored TEXT this slice (§5.3), reconciled in asset slice |
| Adding `dio` to the client | Flagged for review before adding |
| Long-lived JWT (no refresh) | Acceptable for anonymous device slice; refresh with real auth |
| Two-stack slice harder to verify | Backend independently testable via pytest; client via analyze + mocked-transport unit tests |
| §11 example fields differ from client | API follows the client shape; divergence documented (§4) |

## 12. What "done" looks like

1. `docker compose up` + Alembic migrate + seed → Postgres holds the 5 stories.
2. FastAPI serves all §6 endpoints; pytest green including the contract test.
3. Flutter app, pointed at the backend, browses the library, opens/plays a story,
   creates a child profile, and records sessions/events end-to-end — with the
   same screens as today.
4. `flutter analyze` clean; client unit + content-parsing tests green.
