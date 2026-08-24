# Native AR Story Reader - Design Spec

> Replaces the 2D camera-preview AR overlay with the real ARKit/ARCore
> character reader, and makes it work for every story - curated and
> user-recorded alike. One AR session reads a whole story aloud, page by page,
> from a character standing on the child's table.
> Builds on the scan-any-page character reader (`2026-08-14`), its Android
> parity work (`2026-08-21`), and capture-to-story (`2026-08-23`).

**Date:** 2026-08-23
**Status:** Draft design - awaiting review

---

## 1. Goal

Today a recorded (authored) story has no AR at all, and curated stories get a
2D overlay that is not really AR.

The in-player AR button is gated on `arScene != null`
(`lib/features/player/story_player_screen.dart:196`), and authored stories
never get an `ar_scenes` row - `create_authored` writes only story, pages and
one narration segment per page
(`backend/app/repositories/stories.py:68-110`). So the button never appears.
Curated stories do have scenes, but `ArStoryScreen` renders `scene_json` as
Flutter widgets over a `camera` preview, with
`ArCapabilities.nativeImageTrackingWired = false`
(`lib/features/ar/ar_scene_controller.dart:27`).

Meanwhile a genuine, working plane-detection AR reader already exists in this
repo - ARKit on iOS (`ios/Runner/CharacterReader/`), ARCore + SceneView on
Android (`android/app/src/debug/kotlin/.../characterreader/`) - but it is
reachable only from the scan-any-page demo, plays exactly one audio file, and
on Android ships in debug builds only.

This slice points that reader at the library:

```text
open any story in the player
  -> tap "See in AR"
  -> point the device at a table
  -> tap to place a 3D character
  -> the character reads page 1 aloud
  -> tap next/prev to move through the whole story in AR
  -> close, and the book reopens on the page AR ended on
```

The success moment is: a child records their own picture book into the app,
then sits at the kitchen table while a character reads it back to them.

## 2. Decisions

Settled before the design. Not open.

| Decision | Choice |
| --- | --- |
| AR type | Plane detection - character in the room. No printed book needed. |
| Image-target tracking | Out of scope. `nativeImageTrackingWired` never flips; the file is deleted. |
| Multi-page | One AR session for the whole story, with prev/next inside AR. |
| Android build | ARCore/SceneView/Compose promoted from debug to release. |
| Scope | Native reader for every story. The 2D `ArStoryScreen` path is retired. |
| Deletions | Client AR screens only. Backend, `ar_scenes` and seeded `scene_json` are kept. |
| Pages with no clip | `flutter_tts` synthesizes a file in Dart. |

### 2.1 What is explicitly not being done

- No image-target / printed-page anchoring.
- No changes to the scan-any-page flow or its `openCharacterReader` method.
- No backend changes. `manifests.py`, the `ar_scenes` table and the
  hand-authored `scene_json` in `assets/data/*.json` all stay exactly as they
  are, unused.
- No new AR content authoring. The character is the existing bundled model.

## 3. The central problem: the reader needs local files

This is the part of the slice that carries the risk. The AR code already
works; the audio plumbing does not exist.

The native reader plays local files (`MediaPlayer.setDataSource` on Android,
`AVAudioPlayer` on iOS) whose paths must pass a validator. The in-app player
resolves audio three entirely different ways
(`lib/features/player/narration_player.dart:16-27`):

| Story kind | Source | Local file? |
| --- | --- | --- |
| Curated with a registered clip | signed URL from `POST /v1/assets/sign` | No - streamed by just_audio |
| Authored | `POST /v1/tts` -> `systemTemp/narration_<segmentId>.mp3` | Yes, but the wrong filename |
| Either, no clip resolved | on-device `flutter_tts` | No - no file at all |

So AR needs a preparation step that turns any page into playable local files.

### 3.1 Segments, not pages

A page is not one clip. Curated pages carry several narration segments -
`assets/data/bunny_and_the_moon.json` has 2-3 segments on pages 1, 2, 3 and 5,
and `the_brave_little_fox.json` page 1 has 2 - each with its own
`audio_asset_id`. Authored pages always have exactly one
(`backend/app/repositories/stories.py:103`).

A "one file per page" design would silently drop every segment after the first
and read half of each curated page aloud. **The unit of preparation is the
segment; the unit of navigation is the page.**

Concatenating a page's segments into one file was considered and rejected:
iOS device-TTS output cannot be MP3 (see 3.3), so a page can legitimately mix
`.mp3` and `.caf` sources, and joining across codecs needs a real audio
library. The native reader already plays a queue; playing a page's segments in
order is the same mechanism it already has.

### 3.2 The directory is `Directory.systemTemp` - not "the cache dir"

The validators root at `activity.cacheDir` on Android
(`CharacterReaderBridge.kt:194`) and `FileManager.temporaryDirectory` on iOS
(`CharacterReaderBridge.swift:44-46`).

Dart's `Directory.systemTemp` satisfies both. This is not a guess - it is the
pairing the shipped scan-any-page flow already uses
(`lib/features/scan_any_page/tts_client.dart:90,165`).

`path_provider`'s `getApplicationCacheDirectory()` **must not** be used. On
iOS it returns `Library/Caches`, which is not under `tmp`, so every path would
be rejected and AR would never open on iOS. `getTemporaryDirectory()` is an
acceptable equivalent; `Directory.systemTemp` is the one already proven here.

### 3.3 Device TTS cannot write MP3 on iOS

`flutter_tts` 4.2.5 writes via `AVAudioFile(forWriting:)`, which derives the
container format from the file extension, and iOS cannot encode MP3. Creation
throws, and the failure is recorded inside the async buffer callback *after*
the method has already replied - so Dart observes success while no file
exists, and the reader then fails with `audio_missing`.

Therefore:

- **iOS device-TTS output is `.caf`.**
- **Android device-TTS output is `.wav`.** (Android writes WAV bytes
  regardless of the extension; naming it `.wav` keeps the file honest.)
- The validator allowlist must accept these extensions, not just `.mp3`.

Android also needs `awaitSynthCompletion(true)` before synthesis and the
full-path form of `synthesizeToFile`; the default is fire-and-forget and
returns before the file is written, which would launch AR against a
half-written file.

> **Verify at implementation time:** the exact `flutter_tts` Dart signature for
> full-path synthesis (`synthesizeToFile(text, fileName, isFullPath)`) against
> the pinned 4.2.5 API, and confirm on-device that `.caf` output plays through
> `AVAudioPlayer`.

## 4. Architecture

```text
StoryPlayerScreen
  |
  | tap "See in AR"
  v
ArReaderController  (new, Dart, unit-testable)
  |-- 1. capability probe  -> channel: isStoryReaderSupported
  |-- 2. ArNarrationBundle -> prepares files under Directory.systemTemp
  |-- 3. NativeStoryReader -> channel: openStoryReader
  v
native reader (ARKit / ARCore, existing, extended with page navigation)
  |
  | returns {terminalCode, lastPageId, pagesRead}
  v
StoryPlayerScreen  -> jump to lastPageId, record page_viewed for pagesRead
```

Three new Dart units, one extended native contract, no new backend.

## 5. Components

### 5.1 `ArNarrationBundle` (new)

`lib/features/ar/ar_narration_bundle.dart`

**What it does.** Turns a `StoryDetail` into a list of pages, each holding an
ordered list of local audio file paths ready for the native reader.

**How you use it.**

```dart
final bundle = await ArNarrationBundle.prepare(
  detail: detail,
  storyId: story.id,
  resolver: assetUrlResolver,
  fetcher: playerFetcher,   // the player's instance - see 5.1.3
  tts: flutterTts,
  directory: Directory.systemTemp,
  onProgress: (done, total) => ...,
);
```

**What it depends on.** `AssetUrlResolver`, `NarrationAudioFetcher`,
`FlutterTts`, `dart:io`. Every one is injected, so it unit-tests with fakes and
a temp directory.

#### 5.1.1 Per-segment resolution

For each segment of each page, in `sort_order`:

1. Segment has an `audio_asset_id` that resolves to a signed URL -> download
   the bytes to the target path.
2. Story is authored -> take the path from the supplied
   `NarrationAudioFetcher` and **copy** the bytes to the target path.
3. Otherwise -> `flutter_tts` synthesizes to the target path.

#### 5.1.2 Filenames are story-scoped

```text
ar_<sanitizedStoryId>_p<pageNumber>_s<sortOrder>.<ext>
```

- `sanitizedStoryId` is the story id with every non-alphanumeric character
  removed, truncated to 32 characters.
- `pageNumber` is the 1-based `StoryPage.pageNumber`. `sortOrder` is the
  segment's `sort_order`. **Neither is a list index.** (This is the off-by-one
  the design is most likely to produce; page *indices* appear only in
  `initialPageIndex`, and even there the return value is a page *id*.)
- `ext` is one of `mp3`, `wav`, `caf`, `m4a`.

Story scoping exists because the directory persists between runs. Without it, a
prep failure would leave the previous story's file in place, passing validation,
and AR would narrate the wrong book.

#### 5.1.3 The fetcher must be the player's instance

`narrationAudioFetcherProvider` is `autoDispose` and is read without a listener
in `initState` (`story_player_screen.dart:71-73`), so the provider is disposed
after the first frame and its cache is cleared (`di.dart:113-123`). A fresh
`ref.read` inside the AR handler would build a new fetcher with an empty cache
and issue N redundant `POST /v1/tts` calls.

`_PlayerBodyState` already holds the fetcher it gave to `NarrationPlayer`. That
same instance is passed to `prepare`.

The bundle **copies, never renames**. The fetcher's cached `Future` keeps
handing the player the original `narration_<segmentId>.mp3` path; renaming it
would leave the player holding a dangling path once AR returns.

A page carrying no segments at all falls back to synthesizing from
`StoryPage.pageText`. If that is empty too, preparation fails - see 5.1.4.
Every page in the bundle ends up with at least one file.

#### 5.1.4 Failure is all-or-nothing

Before preparing anything, every target path for this story is deleted. If any
segment fails to prepare, the whole bundle fails and AR does not open. Partial
bundles are not offered - a skipped page would break the page-id mapping and
risk playing a stale file.

### 5.2 `NativeStoryReader` (new)

`lib/features/ar/native_story_reader.dart`

A thin `MethodChannel` wrapper in the same shape as `NativeCharacterReader`, on
the **same channel** (`storybook_ar/character_reader`) with two new methods.
It owns no logic beyond argument marshalling and error mapping.

### 5.3 `ArReaderController` (new)

`lib/features/ar/ar_reader_controller.dart`

**What it does.** Sequences probe -> prepare -> open -> return, and exposes a
state enum the screen renders. Holds no Flutter types, so the whole flow is
unit-testable.

States: `idle`, `checkingSupport`, `preparing(done,total)`, `opening`,
`reading`, `failure(code)`.

### 5.4 Native reader: page navigation

Both platforms already place and hold a single anchor. Confirmed sound for this
use: on Android the anchor lives in Compose state
(`CharacterReaderScene.kt:98,173,187-198`) and is untouched by MediaPlayer
changes on the activity; on iOS `AnchorEntity(world:)` persists, and
`applicationDidBecomeActive` re-runs the session without reset options so the
world map survives backgrounding.

Extensions required:

- Hold `pages: List<Page>` and `currentPageIndex` instead of one audio file.
- Within a page, play `audioFilePaths` in order, advancing on completion.
- Overlay gains `prev` / `read-pause` / `next` and a "Page n of N" label.
- Page change swaps the audio data source **only**. The anchor, the loaded
  model and the AR session are untouched.
- Track every page id that began playback, for `pagesRead`.

Existing audio-focus, lifecycle-pause and error behaviour is unchanged.

> **Known limitation, unchanged by this slice:** both readers loop animation
> clip index 0 only, so the character performs one looping motion for the whole
> story regardless of page.

## 6. Native contract

Existing `openCharacterReader` (single file, scan-any-page) is **unchanged**.
Two methods are added to the same channel.

### 6.1 `isStoryReaderSupported`

```text
args:    none
returns: bool
```

A cheap capability probe - `ArCoreApk.checkAvailability` on Android,
`ARWorldTrackingConfiguration.isSupported` on iOS. It exists so an unsupported
device never shows the AR button, rather than letting the child sit through the
full preparation and then fail.

### 6.2 `openStoryReader`

```text
args: {
  'pages': [
    {
      'pageId':         String,
      'pageNumber':     int,
      'audioFilePaths': [String],   // >= 1, in segment sort_order
    },
    ...
  ],
  'initialPageIndex': int,          // 0-based index into 'pages'
}

success: {
  'terminalCode': 'completed' | 'cancelled',
  'lastPageId':   String,
  'pagesRead':    [String],
}
```

#### 6.2.1 Every terminal outcome uses the success channel

This is a deliberate change from `openCharacterReader`, which sends everything
except `"completed"` down `result.error` with no payload
(`CharacterReaderBridge.kt:148-152`). That would throw away `lastPageId` on
cancel - and cancel is the *normal* way to leave AR.

- **`result.success(map)`** for any outcome where the reader was actually
  presented: `completed` and `cancelled`. The outcome is carried in
  `terminalCode`.
- **`result.error(code)`** only for pre-presentation failures, where no page
  was ever read: `ar_unsupported`, `ar_unavailable`, `ar_failed`,
  `model_missing`, `model_load_failed`, `audio_missing`, `audio_failed`,
  `reader_in_progress`.

An audio failure on a *later* page, after the reader is on screen, does **not**
terminate the session. It surfaces in the existing in-scene way ("Audio
couldn't play - Tap Retry") and the child can retry or navigate away. Only an
audio failure during initial preparation - before anything is presented - is a
terminal `audio_failed`. This differs from `openCharacterReader`, where the
single file and the session had the same lifetime.

#### 6.2.2 Single-flight is shared

`openStoryReader` and `openCharacterReader` share one gate - `OneAtATimeGate`
on Android, `isReaderInProgress` on iOS. Two readers must never be presentable
at once, and they are on the same channel.

### 6.3 Path validation

`AudioPathValidator` (Kotlin) and `CharacterReaderAudioPathValidator` (Swift)
change in two ways:

1. They validate **every** path in the request, not one.
2. The hardcoded basename check becomes an anchored pattern allowlist:

```text
^scan_any_page_narration\.mp3$
^ar_[A-Za-z0-9]{1,32}_p\d{1,4}_s\d{1,4}\.(mp3|wav|caf|m4a)$
```

**The containment rule is unchanged.** Every resolved path must still sit under
`cacheDir` / `temporaryDirectory` after symlink resolution. That is the actual
security property - it is what stops an arbitrary-file-read - and relaxing the
basename does not weaken it.

Both validators check the basename **twice**, before and after symlink
resolution (`AudioPathValidator.kt:13,17`;
`CharacterReaderBridge.swift:22-23`). The new pattern must be applied to both
checks in both files.

## 7. Player integration

`lib/features/player/story_player_screen.dart`

### 7.1 The AR gate

```dart
// was: arScene != null && (profile?.arEnabled ?? true)
final arAvailable = (profile?.arEnabled ?? true) && _storyReaderSupported;
```

`_storyReaderSupported` is resolved once via `isStoryReaderSupported` and
cached in state. `arSceneForPage` is gone along with the screen it fed.

The `arAvailable`/`hasQuestions` layout in `_PlayerControls`
(`story_player_screen.dart:410-436`) is otherwise untouched - AR simply becomes
available far more often than it used to be.

### 7.2 The preparation window must block

Preparation takes seconds. During it the user must not be able to reach the
player, because three separate things break
(`story_player_screen.dart:113-134`, `tts_client.dart:107-124`):

- tapping play starts in-app audio that then keeps playing underneath the
  native AR activity,
- swiping sends a stale `initialPageIndex`,
- popping the route disposes `NarrationPlayer` -> `fetcher.dispose()` ->
  `TtsClient.dispose()` deletes `narration_*.mp3` mid-copy.

So preparation runs behind a **non-dismissible modal** showing progress and a
single Cancel action, and `onAr` is guarded against re-entry.

### 7.3 Returning from AR

```text
success -> jump to indexOf(lastPageId), suppressing autoplay
        -> record a page_viewed event for each id in pagesRead
error   -> stay on the current page, show a failure sheet
```

Autoplay is suppressed on this one page load. Today `_goToPage` ->
`_onPageChanged` -> `_loadPage(autoplay: true)`
(`story_player_screen.dart:131-134`), which would immediately re-narrate in the
app the page the character just finished reading in AR.

`pagesRead` exists so sessions and the parent dashboard do not undercount:
pages read inside AR never pass through `_loadPage`, so without it they would
never reach `updateLastPage` or `page_viewed`.

## 8. Error handling

Reuses the existing codes; no new failure vocabulary except at the prepare
step, which is pure Dart.

| Code | Meaning | Recovery offered |
| --- | --- | --- |
| `narration_unavailable` | bundle preparation failed | Retry / Keep reading in the app |
| `ar_unsupported` | device cannot do AR | Keep reading in the app (button is normally hidden) |
| `ar_unavailable`, `ar_failed` | session would not start | Retry / Keep reading |
| `model_missing`, `model_load_failed` | bundled character unavailable | Keep reading |
| `audio_missing`, `audio_failed` | validator rejected a path, or the first page would not prepare | Retry / Keep reading |
| `reader_in_progress` | a reader is already open | ignored - not surfaced |
| `cancelled` | child closed AR | not an error; jump to `lastPageId` |

Preparation failure keeps the child in the book. AR is an enhancement; losing
it must never block reading.

## 9. Android release promotion

The current split is deliberate - `build.gradle.kts:57-59` says debug-only AR
is what keeps the release manifest AR-free. This slice reverses that decision.

| Change | Detail |
| --- | --- |
| Kotlin sources | `src/debug/kotlin/.../characterreader/` -> `src/main/kotlin/.../characterreader/` |
| Bridges | `src/debug/.../ScanAnyPageBridges.kt` -> `src/main/`; delete the `release/` and `profile/` variants |
| **Model asset** | `src/debug/assets/scan_any_page_character.glb` -> `src/main/assets/`, with `ASSET_LICENSE.md` |
| Dependencies | `debugImplementation` -> `implementation` for ARCore, arsceneview, activity-compose, compose-bom, compose ui, compose foundation |
| Compose workaround | delete the `compileOnly` / `testCompileOnly` runtime shims (`build.gradle.kts:82-88`) - they exist only because Compose was debug-only |
| Manifest | move `<uses-feature android:name="android.hardware.camera.ar" android:required="false">` and `<meta-data android:name="com.google.ar.core" android:value="optional">` from `src/debug/AndroidManifest.xml` into `src/main/AndroidManifest.xml`, along with the `CharacterReaderActivity` declaration |
| Tests | `src/testDebug/kotlin/` -> `src/test/kotlin/` |

**The model asset move is not optional.** `modelExists()` opens the model from
`assets` (`CharacterReaderActivity.kt:245-252`); left in the debug source set,
every release `openStoryReader` would exit `model_missing`.

**Leave behind in the debug overlay:** `usesCleartextTraffic="true"` and the
debug `INTERNET` permission. Those are development affordances for reaching a
local HTTP backend and must not reach release.

Verified as non-blocking: arsceneview 4.18 is minSdk 24 (matching the app),
ships consumer ProGuard rules that keep Filament/ARCore/kotlin-math for JNI,
already contributes `com.google.ar.core=optional` from its own manifest, and
bundles 16 KB-aligned Filament. One R8 release build must still be smoke-tested
as part of the work.

Play Store metadata: AR is declared **optional**, so the listing stays
available to non-AR devices. That is why the capability probe in 6.1 matters.

## 10. Deletions

Confirmed scope: **client AR screens only.**

### 10.1 Deleted

```text
lib/features/ar/ar_story_screen.dart
lib/features/ar/ar_scene_controller.dart          (ArCapabilities, ArTrackingMode)
lib/features/ar/scan_story_screen.dart            ("Scan the book" feature)
lib/features/ar/scan_flow_controller.dart
lib/features/ar/simulated_page_detector.dart
lib/features/ar/page_detector.dart
lib/features/ar/simulated_page_panel.dart
lib/data/sources/image_target_resolver.dart
lib/data/models/image_target_manifest.dart
lib/data/models/image_target_manifest.freezed.dart
lib/data/models/image_target_manifest.g.dart

test/scan_flow_test.dart
test/simulated_page_detector_test.dart
test/image_target_resolver_test.dart
test/image_target_manifest_test.dart
```

Also removed: `imageTargetResolverProvider` and `pageDetectorProvider`
(`di.dart:49-65`); routes `/story/:storyId/ar/:pageId` and
`/story/:storyId/scan`; the `AppRoutes.ar()` and `AppRoutes.scan()` helpers
(`app_router.dart:30-32`); the "Scan the book" tile in the library sheet
(`library_screen.dart:238-247`); and the `ar_scenes` assertions in
`test/content_parsing_test.dart:40`.

`models.dart` does not export `image_target_manifest`, so no hidden import
breaks. The four listed tests are the only test references.

### 10.2 Kept, deliberately

- **Backend**: `manifests.py` router and repository, the `ar_scenes` table, the
  `ImageTargetEntry` schemas.
- **Content**: every `scene_json` block in `assets/data/*.json`. This is
  hand-authored and its loss would be irreversible.
- **Model fields**: `ArScene`, `StoryDetail.arScenes`, `StoryPage.imageTargetId`
  and `hasImageTarget`, `ArAnchorType.imageTarget`. These mirror backend schema
  that is being kept; removing them would desynchronise the client model from
  the API for no gain.

Dead but harmless is the intended end state, not an oversight.

## 11. Testing

Per the project's development guidelines, no widget, e2e or integration tests
are run during implementation.

**Dart unit tests**

| Target | Covers |
| --- | --- |
| `ar_narration_bundle_test.dart` | all three resolution branches; multi-segment pages; filename construction incl. pageNumber-vs-index; stale-file cleanup; all-or-nothing failure; copy-not-rename |
| `ar_reader_controller_test.dart` | probe -> prepare -> open -> return sequencing; failure mapping; re-entry guard |
| `native_story_reader_test.dart` | argument marshalling; success-map parsing; error mapping |

**Kotlin JVM tests** (in `src/test/`, after the source-set move)

| Target | Covers |
| --- | --- |
| `AudioPathValidatorTest` | new pattern allowlist on both checks; multi-path; containment still rejects escapes and symlinks |
| `CharacterReaderBridgeTest` | `openStoryReader` argument parsing; shared single-flight gate; success-channel terminal codes |
| page navigation state | index clamping; `pagesRead` accumulation; segment advance within a page |

**Swift tests** — extend `ios/RunnerTests/CharacterReaderTests.swift` for the
same validator changes.

**Manual on-device**, unavoidable for this slice: place-and-read on a real
Android device and a real iPhone; page navigation preserving the anchor; a
release Android build (R8) reaching AR; iOS `.caf` device-TTS playback.

## 12. Risks

| Risk | Mitigation |
| --- | --- |
| Up-front preparation cost - N segments of download or TTS before AR opens | Blocking modal with per-segment progress and Cancel. If it proves too slow on a long story, prepare page 1, open, and fill the rest in the background with next disabled until ready. Not in this slice. |
| Curated audio may not resolve at all if `register_assets.py` has never run | Branch 3 covers it - AR falls back to device TTS and still works, but sounds like the dev-preview voice |
| `flutter_tts` file synthesis behaves differently per platform | Pinned formats (3.3), plus mandatory on-device verification |
| One looping animation for the whole story | Accepted, pre-existing, documented |
| APK growth from Compose + ARCore + SceneView in release | Accepted as the cost of the chosen decision; measure on the first release build |
| The 2D `scene_json` experience is retired | Data and content are kept, so it is recoverable if the native reader disappoints on-device |

## 13. To verify during implementation

These are verification tasks, not undecided design.

1. The exact `flutter_tts` 4.2.5 full-path synthesis signature, and that `.caf`
   output plays through `AVAudioPlayer` on a real iPhone (3.3).
2. That an R8 release build on Android reaches AR with the moved model asset
   (9).

**Decided, revisit later:** an AR reading reuses the player's existing
`StorySession` and records `page_viewed` for `pagesRead` on return, rather than
opening its own session. This keeps the change small and the dashboard counts
honest. A distinct AR session mode may be worth adding once the feature has
been used on-device, but it is out of scope here.

## 14. Size note

This slice is large for a single plan: three new Dart units, a contract change
across two native platforms, an Android build-variant promotion, and a
deletion pass. The implementation plan should sequence it so the app compiles
and the existing scan-any-page reader keeps working at every step - the
Android promotion and the deletions in particular are independent of the AR
reader work and can land before or after it.
