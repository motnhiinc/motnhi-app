# Capture-to-Story - Design Spec

> Lets a user scan several physical pages in a row and save them as a new,
> backend-persisted story that appears in the library and plays in the normal
> player.
> Builds on the existing scan-any-page flow (`2026-08-14`) and its Android
> parity work (`2026-08-21`). It does not replace or modify that demo flow.

**Date:** 2026-08-23
**Status:** Approved design - ready for implementation planning

---

## 1. Goal

The app today is read-only: there is no way to create a story. Stories are
seeded into Postgres from `assets/data/*.json` by `backend/seed.py`, and
`/v1/stories` exposes only `GET`.

This slice adds the missing authoring path, reusing the capture pipeline that
already works:

```text
tap "Create story"
  -> scan a page (existing native scanner + OCR)
  -> correct the recognized text
  -> repeat for as many pages as wanted
  -> name the story and save
  -> the story appears in the library
  -> it opens in the normal player and is narrated in the OpenAI voice
```

The success moment is: a child photographs the pages of their own picture book
and then reads it back inside the app, narrated aloud.

## 2. Decisions

These were settled before the design and are not open:

| Decision | Choice |
|---|---|
| Persistence | Backend, not device-local |
| Page content | Multi-page, **text only** - no page images |
| Ownership | The `users` row behind the device account |
| Narration | OpenAI voice via `POST /v1/tts`, fetched on **every read**, never persisted server-side |
| Build gating | Ships in **release**, not debug-only |

The text-only decision means the native scan bridge contract stays
`String`-returning and no native scanner code changes.

## 3. Scope

### 3.1 In scope

- `stories.owner_user_id` and a nullable-owner model for authored stories.
- `POST /v1/stories` and `DELETE /v1/stories/{story_id}`.
- Ownership filtering across **all five** story read paths.
- A new Flutter `story_composer` feature: multi-page draft, edit, save.
- A third narration audio source in `NarrationPlayer`.
- Promotion of the Android ML Kit scanner from `src/debug` to `src/main`.

### 3.2 Out of scope

- Local persistence of an in-progress draft.
- Editing or re-ordering a story after it is saved.
- Page images, cover art, AR scenes, or questions for authored stories.
- Sharing authored stories between accounts.
- Moderation or safety review of captured text.
- Promoting the ARCore character reader to release. It stays debug-only.

---

## 4. Backend

### 4.1 Migration `0004_authored_stories`

Add one column:

```python
op.add_column("stories", sa.Column("owner_user_id", sa.String(), nullable=True))
op.create_foreign_key(
    "fk_stories_owner_user_id", "stories", "users", ["owner_user_id"], ["id"]
)
op.create_index("ix_stories_owner_user_id", "stories", ["owner_user_id"])
```

`NULL` means curated/seeded - every existing row, so nothing is backfilled.
Non-null means authored by that user.

**No `ondelete` on this FK.** No content-table FK in this schema declares one
(`story_pages.story_id`, `narration_segments.story_id`, and the rest are all
bare constraints in `0001_initial.py`), so a DB-level user delete would cascade
into `stories` and immediately fail against `story_pages`. There is no
user-delete endpoint today. Do not write code that assumes deleting a user
cleans up their stories.

### 4.2 `POST /v1/stories`

Request:

```json
{
  "title": "Bo's Trip to the Moon",
  "language_code": "en",
  "pages": [
    { "page_number": 1, "page_text": "Once upon a time..." },
    { "page_number": 2, "page_text": "The rocket went up." }
  ]
}
```

Server-generated per story:

- `id` - `uuid4()` string.
- `slug` - `authored-<uuid4>`. `stories.slug` is `UNIQUE`. The `authored-`
  prefix is **reserved**: no seed file may use it.
- `owner_user_id` - the authenticated caller.
- `content_status` - `"published"`, so the existing `list_published` filter
  passes it through.
- `themes` - `[]`.
- `age_min` / `age_max` - schema defaults (3/8).
- `duration_seconds` - estimated from total word count at 130 words per minute,
  minimum 60. A literal `0` renders as "0 min" on the library card
  (`lib/features/library/library_screen.dart:181`).

Per page, the server writes a `StoryPage` **and exactly one**
`NarrationSegment`:

| Field | Value |
|---|---|
| `speaker_key` | `"narrator"` |
| `text` | the page text |
| `voice_id` | `settings.openai_tts_voice` |
| `sort_order` | `0` |
| `audio_asset_id` | `NULL` |
| `start_ms` / `end_ms` | `0` |

A null `audio_asset_id` is what routes playback to the TTS path in §6.

This shape is deliberate: an authored story deserialises into exactly the same
`StoryDetail` a curated story does, so `StoryPlayerScreen` needs no structural
change.

Write story, pages, and segments in **one transaction**. A partial save must be
impossible.

### 4.3 Validation

| Rule | Limit | On violation |
|---|---|---|
| `title` | 1-120 chars, stripped | 422 |
| `pages` | 1-50 entries | 422 |
| `page_text` | 1-4000 chars, stripped | 422 |
| `page_number` | contiguous `1..N`, no gaps or duplicates | 422 |
| `language_code` | `en` or `vi` | 422 |
| Stories per user | max 100 authored | 409 |

The 4000-char limit matches the existing `ConfirmedText` constraint in
`backend/app/routers/tts.py:12`, so a page that saves is always a page the TTS
endpoint will accept.

`page_number` contiguity matters because `StoryDetail.orderedPages`
(`lib/data/models/story_detail.dart:30-31`) and the player's
`updateLastPage(page.pageNumber)` both become ambiguous with gaps or
duplicates.

### 4.4 Ownership filtering - all five read paths

Every path that can reach a `stories` row or its children must apply:

```sql
owner_user_id IS NULL OR owner_user_id = :user_id
```

| # | Location | Change |
|---|---|---|
| 1 | `list_published()` - `backend/app/repositories/stories.py:10` | takes `user_id`, adds the predicate |
| 2 | `get_detail()` - `backend/app/repositories/stories.py:23` | takes `user_id`, returns `None` for another user's story |
| 3 | `start_session()` - `backend/app/routers/sessions.py:24` | the bare `db.get(Story, body.story_id)` gains the owner check |
| 4 | `build_image_target_manifest()` - `backend/app/repositories/manifests.py:11` | the bare `db.get(Story, story_id)` gains the owner check |
| 5 | `DELETE /v1/stories/{id}` (new, §4.5) | owner-only |

Paths 3 and 4 leak no content, but both are existence oracles that break the
"404 everywhere" contract. Path 3 also matters for correctness: a session
another user created against an authored story would permanently block its
delete (§4.5).

`backend/app/routers/assets.py` needs **no** change. Authored stories register
no assets, and `sign()` already filters against the `assets` table.

All five return **404**, never 403. A 403 confirms the id exists.

Both story router handlers currently discard the user as
`_: User = Depends(get_current_user)` (`backend/app/routers/stories.py:17,27`).
They start using it.

### 4.5 `DELETE /v1/stories/{story_id}`

Owner-only. 404 for an unknown id, another user's story, or any curated story.

**The naive implementation is a guaranteed 500.** `Story` declares
`cascade="all, delete-orphan"` relationships to `pages`, `segments`,
`ar_scenes` and `questions` (`backend/app/models/__init__.py:80-83`), so those
four are handled. It has **no relationship to `StorySession`**, and
`story_sessions.story_id` is a bare FK with no `ondelete`
(`backend/migrations/versions/0001_initial.py:136`). The player opens a real
backend session on every read (`lib/features/player/story_player_screen.dart:72-81`),
so `create -> read -> delete` raises a Postgres FK violation.

The delete path therefore explicitly removes, in order:

1. `interaction_events` whose `story_session_id` belongs to a session for this story
2. `story_sessions` for this story
3. the `Story` itself, letting the ORM cascades clear pages, segments, ar_scenes and questions

**The regression test must be read-then-delete.** A create-then-delete test
passes while the bug is fully present.

### 4.6 `is_authored` on the wire

Story entries gain `is_authored: bool`, computed as
`owner_user_id IS NOT NULL`. No user ids go on the wire.

This must appear in **both** `LibraryResponse` entries **and** the `story`
object inside `StoryDetailResponse`. The player reads its `Story` from
`GET /v1/stories/{id}` via `storyDetailProvider`
(`lib/features/player/player_providers.dart:7-10`); if the detail response
omits the field it decodes to `false` and the narration fetcher (§6.1) is never
engaged.

### 4.7 Backend tests

- A user sees curated stories plus their own, and not another user's, in both list and detail.
- Another user's authored story 404s on detail, on session start, and on the image-target manifest.
- Delete is owner-only; a curated story cannot be deleted.
- **Read-then-delete** succeeds and leaves no orphaned sessions or events.
- Delete cascades pages and segments.
- Each validation rule in §4.3 rejects.
- The 100-story cap returns 409.
- A saved story round-trips through `GET /v1/stories/{id}` with one segment per page.

Backend tests run against real Postgres (`backend/tests/conftest.py`), so FK
violations surface rather than being mocked away.

---

## 5. Flutter - capture and save

### 5.1 Why a new feature directory

`ScanAnyPageController` is `autoDispose`, single-shot, and welded to the TTS
and AR reader lifecycle: it goes scan -> text -> audio -> character. Adding a
page list, a title, and a save call would make it serve two unrelated
purposes. `lib/features/story_composer/` reuses the one genuinely shared piece
- the `ScanService` interface - and leaves the existing demo flow untouched.

### 5.2 `StoryDraft`

In-memory only:

```dart
class StoryDraft {
  final String title;
  final String languageCode;
  final List<DraftPage> pages;   // DraftPage: localId, text
}
```

**Never persisted.** If the app is killed mid-capture the draft is lost. This
is a deliberate scope decision, not an oversight.

`languageCode` defaults to the **active child profile's** language. Without
this, saving a story in a language other than the profile's makes it invisible
after `invalidate(libraryProvider)` - `list_published` filters on
`language_code` and `libraryProvider` passes the profile's
(`lib/features/library/library_providers.dart:23-26`) - so a successful save
looks like a failed one.

### 5.3 `StoryComposerController`

A `Notifier` over `(phase, draft, failureCode)` with phases
`editing / scanning / saving / failure`.

Methods: `addPage()`, `editPageText()`, `removePage()`, `setTitle()`,
`setLanguage()`, `save()`.

`addPage()` calls `ScanService.scanAndRecognize()` and appends the result. It
uses the same **generation-counter staleness guard** as
`ScanAnyPageController`, so a slow scan resolving after the user leaves cannot
write into dead state.

### 5.4 Persistence seam

A new narrow interface:

```dart
abstract interface class AuthoredStoryRepository {
  Future<Story> createStory(StoryDraft draft);
  Future<void> deleteStory(String storyId);
}
```

with `HttpAuthoredStoryRepository`.

Deliberately **not** added to `StoryRepository`: reads need no change at all -
authored stories come back through `GET /v1/stories` like any other - and
widening `StoryRepository` would force stub methods onto `LocalStoryRepository`
(`lib/data/repositories/story_repository.dart:17`), which is currently
referenced nowhere.

### 5.5 Model and library changes

- `Story` gains `@Default(false) bool isAuthored`. `build.yaml` sets
  `field_rename: snake`, so it maps to `is_authored` automatically.
- After a successful save, `ref.invalidate(libraryProvider)`.
- Authored cards show a small badge.

**Known interaction:** authored stories have `themes: []`, and the theme filter
is `s.themes.contains(theme)`
(`lib/features/library/library_providers.dart:29`). Selecting any theme chip
therefore hides every authored story. This is accepted for this slice.

### 5.6 Entry points and gating

- **Create** - a "Create story" action in the `LibraryScreen` app bar. Not
  behind the parental gate and not `kDebugMode`-gated. The premise is a child
  pointing the tablet at their own book.
- **Delete** - behind the parental gate (`/gate`), as a list of authored
  stories with a delete action on `ParentDashboardScreen` (`/parent`), each
  delete behind a confirmation dialog. Delete is destructive and must not sit
  under a long-press in the child UI.
- The existing debug-only "Scan any page" button
  (`lib/features/library/library_screen.dart:52-62`) is left exactly as it is.

### 5.7 Error handling

| Situation | Behaviour |
|---|---|
| Scan cancelled | Return to the draft, pages intact, no error shown |
| Scan failure | Existing `scan:<code>` message, draft intact, retry available |
| Save failure (network/401/422/409) | Draft stays on screen, save button re-enables |
| Partial save | Impossible - single transaction (§4.2) |
| Delete 404 (already gone) | Treated as success |
| App killed mid-compose | Draft lost (§5.2) |

### 5.8 Flutter composer tests

Over a fake `ScanService` and a fake `AuthoredStoryRepository`: add, edit and
remove pages; save disabled until title and at least one page exist; scan
cancellation; scan failure; save failure; language defaulting from the profile;
and a stale-generation scan resolving after reset.

---

## 6. Flutter - narration playback

### 6.1 The third audio source

`NarrationPlayer._playSegment`
(`lib/features/player/narration_player.dart:126-149`) has two branches today: a
signed clip URL via `just_audio`, else on-device `FlutterTts`.

New precedence:

```text
signed asset clip  ->  fetched OpenAI clip  ->  on-device TTS
```

`NarrationPlayer` gains an optional `NarrationAudioFetcher?`. When it is
`null`, behaviour is byte-for-byte what it is today, so curated playback is
unaffected.

**The fetcher is gated on `isAuthored`.** `StoryPlayerScreen` constructs the
player (`lib/features/player/story_player_screen.dart:64`) and passes a
fetcher only when `widget.detail.story.isAuthored` is true; for every curated
story it passes `null`. Without that gate, any environment where
`register_assets.py` has not run would silently convert curated pages into one
OpenAI call each.

Fetched clips are played with `setFilePath`, not `setUrl`.

### 6.2 Per-page fetch, with a staleness guard

`load()` already resolves signed URLs for the page's segments. It gains a
parallel step: for segments with no `audioAssetId`, ask the fetcher for a local
file, building a `Map<segmentId, path>`.

Fetching is **per page, not per story**, so opening a 20-page story does not
fire 20 OpenAI calls up front.

**`load()` has no staleness protection today.** It awaits
`_resolver.resolve()` and then unconditionally writes `_urlByAssetId` and
`usingTtsFallback` (`narration_player.dart:66-87`). `_onPageChanged` fires
`_loadPage` fire-and-forget (`story_player_screen.dart:112-115`), and
`_loadPage` continues after its await into `updateLastPage`, `recordEvent` and
`play()` (`:98-109`).

Today's awaited step is fast URL signing. This design puts a multi-second
OpenAI fetch in exactly that spot, which turns a millisecond race into a
seconds-wide one. Concretely: `load(N)` in flight -> user swipes to `N+1` ->
`load(N+1)` resets `_segments` -> `load(N)` resolves, overwrites the clip map
with page-N data, regresses `last_page_number` to N, and calls `play()` on
page-N+1 segments using page-N's map.

Required:

- A generation counter in `load()`, checked after **every** await before any
  field write.
- The same guard on `_loadPage`'s continuation - its session write and its
  `play()` call are equally stale.
- The play button is disabled while a fetch is in flight, so a tap mid-fetch
  cannot start device TTS a second before the clip lands.

### 6.3 Session cache

An in-memory cache keyed by segment id prevents refetching when the reader
pages back and forth.

It stores **in-flight `Future`s, not finished paths**. Two fetches for the same
segment (page-back before the first resolves) would otherwise rename over the
same filename while `just_audio` holds it open.

The cache's lifetime is bound to its `TtsClient`: a `dispose()` deletes every
generated file, so a cache outliving the client would hand back dangling paths.
The player owns disposal of its own client. Today the only thing that disposes
a `TtsClient` is `ScanAnyPageController.build`'s `onDispose`
(`lib/features/scan_any_page/scan_any_page_controller.dart:95-99`), so without
this the player's temp files accumulate.

### 6.4 `HttpTtsClient` change

`HttpTtsClient` writes to a fixed filename `scan_any_page_narration.mp3` and
tracks one generated file, deleting it on dispose
(`lib/features/scan_any_page/tts_client.dart:29`).

With a `PageView`, page `N+1` can load while page `N` is still playing, and a
second write would clobber the file `just_audio` is reading. So:

- `generate()` takes an optional `fileName`, defaulting to today's value.
- The client tracks the **set** of `(file, ownerOperationId)` it created and
  deletes, on dispose, every entry whose `ownerOperationId` is less than the
  dispose operation's id.

The existing operation queue is strict FIFO (`tts_client.dart:122-124`), so at
dispose time every tracked file was created by an earlier operation. Extending
the single `_generatedFileOwner` int to a set preserves that invariant. Default
behaviour is unchanged, and the existing tests
("serializes generations", "dispose waits for in-flight generation") still
describe the right behaviour.

Writing a second, separate TTS fetcher was considered and rejected: it would
duplicate the Dio call, the content-type regex validation, and the failure-code
mapping - subtle code that is bad to have in two places.

### 6.5 Failure behaviour

- **Fetch fails** (`/v1/tts` unreachable, 401, 429): fall through to on-device
  `FlutterTts`. An authored story is always readable, just in the worse voice.
- **A fetched clip fails at play time**: today the catch at
  `narration_player.dart:139-141` swallows the error and the segment is
  skipped. With one segment per page that is a **completely silent page**, and
  on the last page an instant `isComplete` and a completion dialog with no
  narration. The device-TTS branch moves **inside** that catch.
- `computeTtsFallback` is updated to account for fetched clips, so the banner
  fires only when a segment genuinely ended up on device TTS.
- The banner copy currently calls TTS a "DEV-ONLY" stand-in
  (`narration_player.dart:16-19`). For an authored story it is a
  network-degradation notice, so the authored case gets its own message. The
  curated wording is unchanged.

### 6.6 Player tests

`test/narration_player_test.dart` currently covers only
`computeTtsFallback` - none of the load/loop lifecycle is harnessed, so the
race in §6.2 needs a purpose-built test rather than existing coverage.

- `computeTtsFallback` across all three source types.
- Source precedence in `_playSegment` with a fake fetcher.
- Fetch failure falls through to device TTS.
- Play-time clip failure falls through to device TTS rather than silence.
- **The race:** `load(N)` in flight, `load(N+1)` starts, `load(N)` resolves -
  no field write, no `play()`, no `last_page_number` regression.
- Per-page fetch fires once per page, not per story.
- The session cache dedupes an in-flight fetch.
- The fetcher is not consulted for a non-authored story.
- `HttpTtsClient` with two distinct filenames does not clobber, and `dispose()`
  removes both.

---

## 7. Android release promotion

### 7.1 iOS needs no native change

No `EXCLUDED_SOURCE_FILE_NAMES` remains in
`ios/Runner.xcodeproj/project.pbxproj`, so `ScanAnyPageBridge` and
`PageScannerViewController` already compile into release;
`AppDelegate.swift` registers both bridges with no `#if DEBUG`; and
`NSCameraUsageDescription` is already present (`ios/Runner/Info.plist:15`).
The only iOS-visible change is that the new entry point is not
`kDebugMode`-gated.

### 7.2 Android changes

1. Move `scananypage/` (`ScanAnyPageBridge`, `ReadingOrderSorter`,
   `ScannerFailureMapper`) and `OneShotGate.kt` from
   `android/app/src/debug/kotlin/...` to `src/main/kotlin/...`.
2. Keep three variant copies of `ScanAnyPageBridges`, changing what they do:
   debug registers scanner **and** ARCore reader; release and profile now
   really register the **scanner only** instead of returning today's no-op
   stub. `onHostResume()` stays a no-op outside debug - only the ARCore reader
   needs a resume signal.
3. Move `SCANNER_REQUEST_CODE` (and any other shared constant) out of the debug
   copy's companion object into `src/main`; the release and profile copies need
   it too. `READER_REQUEST_CODE` stays debug-only.
4. Move the two ML Kit dependencies from `debugImplementation` to
   `implementation` (`android/app/build.gradle.kts:57-58`). `com.google.ar:core`,
   `io.github.sceneview:arsceneview` and every Compose dependency stay
   `debugImplementation`.

`ScanAnyPageBridge` imports only ML Kit scanner/text-recognition,
`androidx.lifecycle` (supplied by the Flutter embedding on all variants), and
the two gates - zero ARCore, SceneView or Compose. The existing `compileOnly`
Compose arrangement (`build.gradle.kts:72-79`) keeps working because no release
source references a `@Composable`.

### 7.3 Manifest - unchanged

`android.permission.CAMERA` is already in
`android/app/src/main/AndroidManifest.xml:6`. Only the ARCore half - the
`camera.ar` `uses-feature`, the `com.google.ar.core` meta-data, and
`CharacterReaderActivity` - lives in `src/debug/AndroidManifest.xml`. Promoting
the scanner needs no manifest change and the release manifest keeps **zero AR
entries**.

### 7.4 Test relocation

`ReadingOrderSorterTest` and `OneShotGateTest` move from `src/testDebug` to
`src/test`, so `./gradlew test` covers code that now ships.
`NativeFailureMappingTest` mixes `ScannerFailureMapper` cases with ARCore
`CharacterReader` cases in one file and is split: scanner cases to `src/test`,
reader cases stay in `testDebug`.

### 7.5 Release notes

- `text-recognition:16.0.1` bundles its model: roughly 4 MB of APK growth. The
  document scanner itself is delivered by Play Services.
- The ML Kit document scanner requires Play Services and an on-demand module
  download. A first-run failure maps to `camera_unavailable`, which the
  composer surfaces as a retryable scan error.

---

## 8. Verification

Before this slice is called done:

- `flutter analyze` clean, excepting the pre-existing
  `narration_player.dart:84` `unnecessary_non_null_assertion` warning.
- Full Dart test suite green.
- Backend test suite green against real Postgres.
- `./gradlew test` green.
- Debug, release and profile all compile on both platforms.
- **Merged release manifest check:** dump it and confirm no
  `com.google.ar.core` meta-data, no `camera.ar` `uses-feature`, and no
  `CharacterReaderActivity`.
- Physical-device pass: scan three pages, save, confirm the story appears,
  open it, confirm OpenAI-voice narration on each page, page back and forth to
  confirm no refetch and no audio crossover, then delete it from the parent
  area.

## 9. Open risks

- **Cost.** Every page turn of an authored story is one OpenAI TTS call. A
  child re-reading a 20-page story ten times is 200 calls. There is no rate
  limit on `/v1/tts` beyond authentication. Worth watching before any wider
  release.
- **No offline reading.** Authored stories degrade to on-device TTS without a
  network. That is by design here, but it makes them worse offline than curated
  stories with registered audio assets.
- **No moderation.** Whatever text the camera reads is stored and spoken back.
  Acceptable for a family's own books; not acceptable if authored stories ever
  become shareable.
