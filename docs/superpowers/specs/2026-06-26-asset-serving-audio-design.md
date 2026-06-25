# Asset Serving (audio) — Slice design

**Date:** 2026-06-26
**Status:** Draft for review
**Slice:** Platform slice 3 of N. Slice 1 (Flutter MVP-lite client) and slice 2
(Backend API client-contract + HTTP swap) are built and on `main`. This slice
gives the backend real audio assets to serve and switches narration playback
from on-device TTS to served clips.
**Source spec:** `interactive_storybook_voice_ar_product_technical_spec.md`
(§8.3 MVP audio must-have, §9.4 voice/audio, §9.5.4 audio asset service,
§15.3 data security, §18.1 infra).

---

## 1. Goal

Stand up the audio asset service the existing player already implies, and serve
real per-segment narration clips over signed URLs — with no UI rework. After
this slice, the running app, pointed at the backend, plays a produced recording
for any segment whose clip has been registered, and falls back to on-device TTS
for segments not yet recorded.

This slice ships the **serving infrastructure + a drop-in convention**. The
actual 5-story recordings are produced by hand and supplied by the product owner
later; each dropped file becomes audible with no code change.

## 2. Locked decisions (from brainstorming)

| Decision | Choice |
|----------|--------|
| Storage & serving | **FastAPI + HMAC-signed, expiring URLs**; files under `backend/storage/`; FastAPI streams with HTTP Range. No cloud account. |
| Asset data model | **Real `assets` table** (`asset_id` PK, `kind`, `storage_key`, `content_type`, `byte_size`, `duration_ms`, `created_at`). |
| Asset scope | **Audio only.** Cover/page/character images stay bundled placeholders (own future slice). The `kind` column lets them slot in with no schema change. |
| Audio granularity | **One clip per `narration_segment`.** `start_ms`/`end_ms` stay highlight metadata only. |
| Audio production | **Product owner supplies real recordings.** This slice builds serving + a drop-in convention; no clip-generation tooling. |

## 3. Non-goals (deferred to later slices)

Object storage / CDN (S3/GCS, presigned URLs) · image & AR asset serving ·
the async voice-generation worker · clip generation tooling · per-page gapless
audio with time-range seek · offline caching of clips (§7.1.7) · entitlement
gating of asset access · real parent auth.

---

## 4. Architecture

A two-tier signed-URL model, entirely inside the existing FastAPI app:

1. **Sign tier (authenticated):** the client sends the asset ids it needs; the
   backend returns short-lived signed URLs, but only for ids that have a
   registered file.
2. **Stream tier (public-but-signed):** the media request carries no `Bearer`
   token (so `just_audio` plays the URL directly); FastAPI validates the HMAC
   signature + expiry and streams the file with HTTP Range support.

This is the exact shape the later CDN slice formalizes — that slice swaps
local-file streaming for S3/GCS presigning behind the same two endpoints.

```
client (player)
  │  POST /v1/assets/sign {asset_ids}            (Bearer JWT)
  ▼
FastAPI sign endpoint ──> assets table ──> {asset_id: "/v1/assets/{id}?exp=&sig="}
  │
  │  GET /v1/assets/{id}?exp=&sig=               (no Bearer; signature only)
  ▼
FastAPI stream endpoint ──> validate HMAC+exp ──> FileResponse(storage/<key>) [Range-aware]
```

## 5. Data model — new `assets` table

Additive; no existing table is modified.

| column | type | notes |
|--------|------|-------|
| `asset_id` | `TEXT` PK | stable id, e.g. `aud_seg_bunny_p1_1` |
| `kind` | `TEXT` | `'audio'` this slice; `'image'`/`'ar'` later |
| `storage_key` | `TEXT` | path under `backend/storage/`, e.g. `audio/aud_seg_bunny_p1_1.m4a` |
| `content_type` | `TEXT` | `audio/mp4` for `.m4a` |
| `byte_size` | `INTEGER` null | filled at registration |
| `duration_ms` | `INTEGER` null | optional metadata; populated if cheaply probeable, else null |
| `created_at` | `timestamptz` | server default now |

- SQLAlchemy 2.0 ORM model `Asset` in `app/models/__init__.py`.
- Alembic migration `0003_assets`.
- `narration_segments.audio_asset_id` is unchanged (already `TEXT`, nullable).
  It is **not** a hard FK to `assets` — the content id may exist before the
  binary is produced (see §6).

## 6. Content wiring — `audio_asset_id` pre-population

`audio_asset_id` is **pre-populated on every segment** in the 5 bundled
`assets/data/*.json` files now, using a stable scheme `aud_<segment_id>`
(e.g. segment `seg_bunny_p1_1` → `aud_seg_bunny_p1_1`).

Rationale: the *content* declares "this segment's narration is asset X",
independent of whether the binary exists yet. Consequences:

- When a recording is dropped, **no JSON/seed edit is needed** — the id is
  already present; only an `assets` row + file appear.
- Availability is decided at playback by whether **signing succeeds** (the
  asset has a registered file), not by the id's presence.

Impact on existing files (additive edits, flagged for review):

- `assets/data/*.json` (all 5): add `"audio_asset_id": "aud_<segment_id>"` to
  each segment object.
- `test/content_parsing_test.dart`: update expectations to assert the parsed
  `audioAssetId` on segments.
- The backend **contract test stays exact** — both the bundled JSON and the API
  response now carry the same `audio_asset_id`, so `GET /v1/stories/{id}`
  remains byte-equivalent to the bundled JSON (modulo key ordering).

`seed.py` ingests the new field into `narration_segments.audio_asset_id` like
any other column.

## 7. API surface

All paths `/v1/*`. Enum/field shapes follow the client's serialized models.

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `POST` | `/v1/assets/sign` | Bearer | body `{ "asset_ids": [".."] }` → `{ "<asset_id>": "/v1/assets/<id>?exp=<unix>&sig=<hex>" }`. Only ids with a registered `assets` row + existing file are included; unregistered ids are omitted from the response map. |
| `GET` | `/v1/assets/{asset_id}?exp=&sig=` | signature only | Validates HMAC + expiry, streams the file via Range-aware `FileResponse`. `403` on bad/expired/missing signature; `404` if the asset row or file is missing. |

### 7.1 Signing scheme

- `sig = HMAC_SHA256(ASSET_URL_SECRET, f"{asset_id}:{exp}")` rendered hex.
- `exp = <now + ASSET_URL_TTL_SECONDS>` as a unix timestamp.
- Verification uses `hmac.compare_digest` (constant-time) and rejects
  `exp <= now` (a URL is invalid at or after its expiry second, matching the
  RFC 7519 / signed-URL convention that validity requires `now < exp`).
- New config (in `app/config.py` + `.env.example`):
  - `ASSET_URL_SECRET` — signing key, dev placeholder ≥32 bytes.
  - `ASSET_URL_TTL_SECONDS` — default `3600` (long enough for a story session,
    short enough to be safe; the client re-signs each session).
- The sign endpoint returns **relative** URLs; the client prefixes
  `API_BASE_URL`.

### 7.2 Access scope

Audio clips are shared story content, not per-user data: any authenticated
device may sign any registered content asset. No per-user scoping
(entitlement gating is a separate, deferred slice).

## 8. Storage & registration

- Files live under `backend/storage/audio/`, named `<audio_asset_id>.m4a`
  (e.g. `aud_seg_bunny_p1_1.m4a`). Small demo `.m4a` files may be committed;
  production moves to object storage (non-goal).
- `backend/register_assets.py` (idempotent):
  1. Scans `backend/storage/audio/`.
  2. For each file whose stem matches a known segment `audio_asset_id`, upserts
     an `assets` row (`kind='audio'`, `storage_key`, `content_type='audio/mp4'`,
     `byte_size` from the file, `duration_ms` if cheaply probeable else null).
  3. Warns on **orphan** files (no matching segment id) and reports segments
     **still missing** audio. Does not delete anything.
- The known `audio_asset_id` set is derived from the seeded
  `narration_segments` (so `seed.py` runs first).

## 9. Client changes

Repository interfaces are unchanged. No widget/UI changes.

- **New `AssetUrlResolver`** (`lib/data/sources/asset_url_resolver.dart`):
  - `Future<Map<String,String>> resolve(List<String> assetIds)` — calls
    `POST /v1/assets/sign`, returns `asset_id → absolute URL`
    (`API_BASE_URL` + relative path).
  - Caches resolved URLs with their `exp`; refreshes an id when missing or
    within a small skew of expiry.
  - All calls routed through `ApiClient.send()` (so a `401` re-mints the device
    token, consistent with the other repositories).
  - Wired via Riverpod DI (`lib/core/di.dart`), constructed with the existing
    `apiClientProvider`.
- **`NarrationPlayer`** (`lib/features/player/narration_player.dart`):
  - `load()` resolves the page's segment `audio_asset_id`s up front via the
    injected `AssetUrlResolver`.
  - Per segment: if a URL resolved, play via `_file.setUrl(url)`; otherwise fall
    back to TTS. (Swaps today's `setAsset` → `setUrl`.)
  - `usingTtsFallback` now means "any segment without a *resolvable* clip" —
    truthful while recordings are still pending.
  - The injected resolver is optional/nullable so existing unit tests that
    construct the player without a backend keep working (null resolver ⇒ all
    TTS, current behavior).

## 10. Error handling

- **Bad/expired/missing signature** → `403`; client surfaces nothing special —
  the player simply falls back to TTS for that segment (same as an unresolved
  url). A missing/corrupt clip mid-play already falls through to the next
  segment in the current player.
- **Unknown asset / missing file** → `404` from the stream endpoint; the sign
  endpoint never hands out a URL for it (omitted from the map), so this is only
  reachable via a stale/hand-crafted URL.
- **Backend unreachable** → the existing `AsyncValue` error views surface load
  failures; the resolver returns an empty map ⇒ player uses TTS. Offline
  caching is a deferred feature, not added here.

## 11. Testing & verification gates

**Backend (`pytest`, transactional test DB):**
- `assets` model + migration: round-trip an asset row.
- Sign endpoint: returns signed URLs only for registered ids; omits
  unregistered ids; requires Bearer.
- Stream endpoint: serves a file; honors a `Range` request (`206` + correct
  bytes); rejects bad signature (`403`), expired `exp` (`403`); `404` unknown
  asset.
- `register_assets.py`: creates rows from dropped files; idempotent on re-run;
  flags orphans and missing-audio segments.
- **Contract test stays green** (`GET /v1/stories/{id}` == bundled JSON with the
  new `audio_asset_id` present on both sides).

**Client:**
- `AssetUrlResolver` unit test against a **mocked `dio` transport**: resolves a
  batch, caches, refreshes on expiry, returns empty on transport error.
- `NarrationPlayer` test: with a resolver returning a URL → uses `setUrl`; with
  none → TTS fallback and `usingTtsFallback == true`.
- `content_parsing_test.dart` updated and green (segments expose
  `audioAssetId`).
- `flutter analyze` clean. No widget/integration tests (project rule).

## 12. Risks & open questions

| Risk / question | Handling |
|-----------------|----------|
| `audio_asset_id` present but no binary yet | Availability decided by signing success; player falls back to TTS (§6, §9). |
| Editing the 5 seed JSON files | Additive only (one field per segment); contract + parsing tests updated; flagged for review (§6). |
| Signed URL expiry mid-session | TTL default 3600s; client caches per session and re-signs on expiry (§7.1, §9). |
| `just_audio` Range/streaming from a custom server | `FileResponse` is Range-aware; verified by the `206` test (§11). |
| Committing binary `.m4a` to git | Acceptable for small demo clips; production moves to object storage (non-goal). |
| `audio_asset_id` not a hard FK | Intentional — content id can precede the binary; integrity enforced by `register_assets.py` warnings, not the DB (§5, §8). |

## 13. What "done" looks like

1. Migration `0003_assets` applies; `seed.py` loads stories with
   `audio_asset_id` on every segment.
2. Drop a correctly-named `.m4a` into `backend/storage/audio/`, run
   `register_assets.py` → an `assets` row exists.
3. FastAPI serves `POST /v1/assets/sign` and the Range-aware signed
   `GET /v1/assets/{id}`; pytest green including the contract test.
4. The Flutter app, pointed at the backend, plays the produced clip for that
   segment and falls back to TTS for un-recorded segments; the TTS-fallback
   banner is truthful.
5. `flutter analyze` clean; client unit + content-parsing tests green.
6. The product owner records the 5 stories at leisure; each dropped + registered
   file becomes audible with no code change.
