# Scan-to-Read Recognition — Design Spec

> Platform slice: page-recognition foundation for scan-to-read (Use Case B §6.2, minus AR).
> Companion diagram: `sequence-scan-to-read.html` (built-vs-target sequence).
> Spec references like (§9.5.5) point to `interactive_storybook_voice_ar_product_technical_spec.md`.

**Date:** 2026-07-02
**Status:** Approved design — ready for implementation plan.

---

## 1. Goal

Deliver the page-**recognition** half of scan-to-read: the app opens a known book, the camera "recognizes" which page it is looking at, and the app plays that page's narration. This builds the recognition **contract, data path, and `scan`-session wiring** end-to-end, with a **simulated detector** standing in for native ARKit/ARCore image tracking.

Recognition is the shared foundation for both scan-to-read and the later AR overlay; this slice builds it once so the native matcher and the AR scene/character render each become clean drop-ins.

## 2. Scope

**In scope**
- Backend `GET /v1/stories/{story_id}/image-target-manifest` endpoint (the image-target-manifest responsibility of the AR Asset Service, §9.5.5 / §11.5).
- A manifest schema faithful to what a native matcher will later need.
- Client manifest resolver + a `PageDetector` seam with a manifest-driven simulated implementation.
- Wiring a `mode:"scan"` session end-to-end: detect → start session → play narration → record `scan_success`.
- Seed content: give every page an `image_target_id`.

**Out of scope (explicit non-goals)**
- Native ARKit `ARReferenceImage` / ARCore `AugmentedImageDatabase` matching. Left as a clean drop-in behind the existing `nativeImageTrackingWired` flag.
- Producing or serving page-image **binaries** (the reference-image URL field exists and is real-shaped, but bytes are a separate, art-blocked slice).
- AR scenes, 2D character render, tap-to-play-on-character (the additive AR layer).
- Scan-any / global cross-story recognition. This slice is **book-first**: the story is selected first, then only its pages are matched.

## 3. Identification model — book-first

The user selects a book from the library first; the app loads **that story's** manifest and only needs to resolve which *page* of the known book the camera sees. This matches the spec's per-story endpoint (§11.5), keeps the on-device target set small (5–8 pages) so it stays within ARKit/ARCore database-size limits (§9.3.2), and defers scan-any to a future slice.

## 4. Backend design

### 4.1 Endpoint

```
GET /v1/stories/{story_id}/image-target-manifest
Authorization: Bearer <device JWT>     # Depends(get_current_user), consistent with /v1/stories
```

- New router `app/routers/manifests.py`, registered in `app/main.py`.
- 404 `story not found` when the story id is unknown (mirrors `/v1/stories/{id}`).
- 200 returns the manifest below. A story that exists but has no targeted pages returns `targets: []` (valid, not an error).

### 4.2 Response schema

New Pydantic schemas in `app/schemas/__init__.py`:

```json
{
  "story_id": "story_bunny_forest",
  "version": 1,
  "targets": [
    {
      "page_id": "page_bunny_03",
      "page_number": 3,
      "image_target_id": "imgt_page_bunny_03",
      "reference_image_url": null,
      "physical_width_mm": 210
    }
  ]
}
```

- `ImageTargetManifest`: `story_id: str`, `version: int`, `targets: list[ImageTargetEntry]`.
- `ImageTargetEntry`: `page_id: str`, `page_number: int`, `image_target_id: str`, `reference_image_url: str | None`, `physical_width_mm: int`.

### 4.3 Manifest builder (repository)

New `app/repositories/manifests.py` with a single function:

```
build_image_target_manifest(db, story_id) -> ImageTargetManifest | None
```

- Returns `None` when the story does not exist (router maps to 404).
- `targets` = the story's `story_pages` **where `image_target_id IS NOT NULL`**, ordered by `page_number`.
- `reference_image_url`: signed via the existing `assets_signing.sign_asset_url(page_image_asset_id)` **only if** `page_image_asset_id` is a registered row in `assets`; otherwise `null`. (Today `page_image_asset_id` values are path strings, not registered asset ids, so this is truthfully `null` — the field shape is correct for when image assets are registered later.)
- `physical_width_mm`: a single config default, same for every target this slice.
- `version`: constant `1` for MVP; documented as the future cache-invalidation / content-update hook (§11.5, §9.5.5 "manage asset bundle versions").

### 4.4 Config

`app/config.py` adds:
- `default_target_physical_width_mm: int = 210` (≈ a typical A5 children's-book page width).

No change to the `story_pages` table: `physical_width` stays a manifest-computation concern, so the spec's §10 data model is untouched. No new migration is required by this slice.

### 4.5 Seed / content

Set `image_target_id = "imgt_<page_id>"` for **every** page in all five `assets/data/*.json` files (currently `null`). `seed_story` already reads `image_target_id=p.get("image_target_id")`, so this is a data-only, value-preserving addition — the same pattern as the `audio_asset_id` edit in the audio slice. Giving every page a target makes any page of a known book scannable.

## 5. Client design (Flutter)

### 5.1 Manifest resolver

Mirrors the existing `AssetUrlResolver`:
- `lib/data/sources/image_target_resolver.dart`:
  - abstract `ImageTargetResolver { Future<ImageTargetManifest> fetch(String storyId); }`
  - `HttpImageTargetResolver` — `GET /v1/stories/{id}/image-target-manifest` via `ApiClient.send()` (401 re-mint), caches the parsed manifest by `storyId` (invalidate on `version` change), broad graceful catch consistent with the audio resolver.
- Freezed models in `lib/data/models/`: `ImageTargetManifest { storyId, version, targets }`, `ImageTarget { pageId, pageNumber, imageTargetId, referenceImageUrl?, physicalWidthMm }`.
- DI: `imageTargetResolverProvider` in `lib/core/di.dart`.

### 5.2 Detector seam

- `lib/features/ar/page_detector.dart`: abstract `PageDetector` exposing a single callback seam `void onDetected(String pageId)` (registered by the scan flow). Chosen over a stream to keep the seam minimal, synchronous, and trivially unit-testable; a native detector calls the same callback when a reference image is matched.
- `lib/features/ar/simulated_page_detector.dart`: `SimulatedPageDetector` built from a manifest's `targets`; the scan screen renders a dev panel of pages and a tap emits that page's `page_id` through the same seam the native detector will use.
- Gated behind the existing `ArCapabilities.nativeImageTrackingWired = false` (in `ar_scene_controller.dart`): while false, the scan screen uses `SimulatedPageDetector`; a future native `PageDetector` drops in when the flag flips. DI: `pageDetectorProvider`.

### 5.3 Scan flow orchestration

In the scan/AR screen:
1. Story is already chosen (book-first) → `imageTargetResolver.fetch(storyId)`.
2. Show camera preview (existing `ar_story_screen` camera path) + the simulated page panel.
3. On `onDetected(pageId)` (page must be in the manifest, else no-op):
   - `startSession(mode: SessionMode.scan, ...)` via `http_session_repository`. Confirm `SessionMode.scan` exists in the client enum; add it (serialized `'scan'`) if missing.
   - Drive the existing `NarrationPlayer` to that page; audio resolves via the existing `AssetUrlResolver`, TTS fallback unchanged.
   - Post a `scan_success` interaction event via the existing events path.

**Reuse, not rebuild:** `NarrationPlayer`, `AssetUrlResolver`, `http_session_repository`, and the camera preview are untouched; the scan flow only orchestrates them.

## 6. Data flow

```
pick book (library) → open scan
  → GET image-target-manifest            (new; built this slice)
  → camera preview + simulated panel      (preview reused; detector new)
  → onDetected(page_id)                   (SimulatedPageDetector)
  → POST /v1/story-sessions {mode:"scan"} (existing)
  → NarrationPlayer → assets/sign → GET /assets/{id}  (existing)
  → POST /sessions/{id}/events {scan_success}         (existing)
```

This turns phases ②–③ of `sequence-scan-to-read.html` from missing to built (via simulation), with the native matcher as the only remaining piece for a real camera scan.

## 7. Error handling

| Condition | Behavior |
|---|---|
| Unknown `story_id` | 404 `story not found` |
| Story with no targeted pages | 200 with `targets: []` → client "nothing to scan" state |
| Manifest network failure | client uses cached manifest if present, else graceful error surface (no crash) |
| Detected `page_id` not in manifest | no-op (ignore) |
| Expired / 401 | existing `ApiClient.send()` re-mint |
| Missing audio binary | existing `NarrationPlayer` TTS fallback |

## 8. Testing (TDD)

**Backend**
- `manifests` repository: target selection (only `image_target_id IS NOT NULL`), ordering by `page_number`, `physical_width_mm` default, `reference_image_url` null-vs-signed (registered asset → signed; unregistered path → null), `version` present; unknown story → `None`.
- endpoint: 200 shape, 401 without Bearer, 404 unknown story, empty `targets` for a story with no targeted pages.
- contract/seed test: every seeded page has `image_target_id == f"imgt_{page_id}"`.

**Client**
- `ImageTargetManifest` / `ImageTarget` model parsing.
- `HttpImageTargetResolver`: mocked-dio manifest fetch, cache hit, 401 path, graceful error.
- `SimulatedPageDetector`: emits the manifest's `page_id`s through the seam.
- scan-flow orchestration logic (detection → `scan` session created with `mode:"scan"` → `scan_success` posted) as unit tests.
- No widget / e2e / integration runs during development.

## 9. Units & boundaries

| Unit | Responsibility | Depends on |
|---|---|---|
| `routers/manifests.py` | HTTP endpoint, auth, 404 mapping | `repositories/manifests`, `auth` |
| `repositories/manifests.py` | Build manifest from `story_pages` + sign URLs | `models`, `assets_signing`, `config` |
| `schemas` (`ImageTargetManifest`, `ImageTargetEntry`) | Response contract | — |
| `image_target_resolver.dart` | Fetch + cache manifest over HTTP | `ApiClient`, models |
| `page_detector.dart` / `simulated_page_detector.dart` | Emit detected `page_id` through a stable seam | manifest models |
| scan flow (screen) | Orchestrate detect → session → play → event | resolver, detector, `NarrationPlayer`, session repo |

Each is independently testable; the native detector is a future implementation of the same `PageDetector` seam.

## 10. Follow-ups (not this slice)

- Native ARKit/ARCore `PageDetector` implementation + on-device validation (flip `nativeImageTrackingWired`).
- Page-image binary production + serving (`assets` `kind='image'`), which makes `reference_image_url` non-null and feeds a real reference-image database.
- Image-Target Processing Worker + image-quality validation gate (offline production, §9.3.1).
- AR scene serving + 2D character render + tap-to-play (the additive AR layer on top of this recognition foundation).
- Manifest versioning beyond the constant `1` (real cache invalidation / content updates).
