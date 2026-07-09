# Scan-to-Read Wiring — Design Spec

> Platform slice: wire the committed scan-to-read *foundation* into the app so it is reachable and fires `scan_success` end-to-end.
> Builds on: `2026-07-02-scan-to-read-recognition-design.md` (the foundation: manifest endpoint, resolver, `PageDetector` seam, `ScanFlowController`, `SimulatedPagePanel`).
> Spec references like (§6.2) point to `interactive_storybook_voice_ar_product_technical_spec.md`.

**Date:** 2026-07-09
**Status:** Approved design — ready for implementation plan.

---

## 1. Goal

The scan-to-read foundation (branch `feat/scan-to-read-recognition`, commit `9484e78`) is built and unit-tested but has **zero consumers in `lib/`** and **no route** — so the `scan_success` analytics event (one of the four MVP must-haves) never fires end-to-end. This slice adds the missing UI seam: a **book-first entry point** and a **`ScanStoryScreen`** that hosts the existing `ScanFlowController`, making the flow reachable and lighting up the `scan`-mode session + `scan_success` event.

Detection remains **simulated** (`ArCapabilities.nativeImageTrackingWired = false`): the screen shows a camera preview plus a tappable page list (`SimulatedPagePanel`); a tap stands in for the camera recognizing a page. Native ARKit/ARCore recognition drops in later behind the unchanged `PageDetector` seam. The screen is therefore labeled **"Scan (Preview)"**.

## 2. Scope

**In scope**
- A book-first entry: tapping a library story card opens a **Read / Scan** chooser.
- A route `GET /story/{storyId}/scan` and a new `ScanStoryScreen`.
- Hosting the existing `ScanFlowController` in that screen: `start()` → simulated detect → `scan` session → play page narration → `scan_success`.
- Playing a detected page's narration via the existing `NarrationPlayer` + `AssetUrlResolver` (TTS fallback unchanged).

**Out of scope (explicit non-goals)**
- Native ARKit/ARCore recognition (still behind `nativeImageTrackingWired`).
- Any change to the committed foundation (`ScanFlowController`, `PageDetector`, `SimulatedPageDetector`, `SimulatedPagePanel`, `ImageTargetResolver`, manifest models) — reused as-is. **Exception (decided 2026-07-09, in scope):** one ~3-line robustness fix to `ScanFlowController._ensureSession` (§11).
- Any backend change.
- Opening the full Story Player at a detected page (that needs gap #12, resume-to-page — not built).
- A full story-detail screen (the chooser is a bottom sheet, not a new screen).

## 3. Entry point — book-first chooser

In `lib/features/library/library_screen.dart`, `_StoryCard.onTap` currently does `context.go(AppRoutes.story(id))` (straight to the player). Change it to open a **bottom sheet** with two actions:

- **Read** → `context.go(AppRoutes.story(story.id))` — today's behavior, unchanged.
- **Scan the book** → `context.push(AppRoutes.scan(story.id))`.

Both actions call `Navigator.pop(context)` to **close the sheet before navigating** (hawkeye #6): the bottom sheet is a pageless route above the library page, so `push`-ing scan on top of it would return to the library with the sheet still open. Locked cards remain non-tappable (the existing `locked ? null : …` guard is preserved). Scan uses `push` (not `go`) so back returns to the library. This is the spec's book-first flow (§6.2, §3 of the foundation spec): the story is chosen first, then only its pages are matched.

## 4. Route

In `lib/core/router/app_router.dart`:
- Add `static String scan(String storyId) => '/story/$storyId/scan';` to `AppRoutes`.
- Add a `GoRoute(path: '/story/:storyId/scan', builder: (_, state) => ScanStoryScreen(storyId: state.pathParameters['storyId']!))`, alongside the existing `/story/:storyId/ar/:pageId` route.
- No change to the `redirect` guard: `/story/**` is not under `/parent`, so no gating/redirect interaction. Onboarding gate still applies globally (as for every non-onboarding route).

## 5. `ScanStoryScreen`

New file `lib/features/ar/scan_story_screen.dart`. **Two-widget split, mirroring `ArStoryScreen`**: an outer `ConsumerWidget` resolves the async dependencies and gates on them; an inner `ConsumerStatefulWidget` owns the imperative lifecycle (controller, camera, audio) with values that are **guaranteed already loaded**. This ordering is what makes the dependencies safe — it is not cosmetic (see hawkeye #2/#3 below).

### 5.1 `ScanStoryScreen` (outer, `ConsumerWidget`) — readiness gate
Watches `childProfileProvider` **and** `storyDetailProvider(storyId)` and renders:
- either still loading → `LoadingView`
- error, or null profile, or null detail → `ErrorView`
- both data → `_ScanView(storyId: storyId, detail: d, childProfile: profile)`

Gating on **both** before building `_ScanView` guarantees:
- a **real** `childProfile.id` — never the `'local'` fallback the player uses. The backend 404s a `story-sessions` POST for a profile the device doesn't own (`backend/app/routers/sessions.py`), so `'local'` would make `startSession` fail every time and, worse, that failure is memoized by the controller (hawkeye #3). Passing a resolved id avoids it.
- `detail` is non-null, so the **first** page tap actually plays. With a lazy null read, the first tap found `detail == null` (the library never touches `storyDetailProvider`, so the tap closure was its first access), skipped audio, yet the controller **still** recorded `scan_success` — a silent scan that pollutes the metric (hawkeye #2).

### 5.2 `_ScanView` (inner, `ConsumerStatefulWidget`) — deps
Receives resolved `storyId`, `detail`, `childProfile`. Providers read once in `initState` via `ref.read`:
| Dep | Source |
|---|---|
| `ImageTargetResolver` | `imageTargetResolverProvider` |
| `SessionRepository` | `sessionRepositoryProvider` |
| `PageDetector Function(ImageTargetManifest)` | `pageDetectorProvider` |
| `NarrationPlayer` | constructed with `ref.read(assetUrlResolverProvider)` (as AR screen) |
| `childProfileId` / `languageCode` | `widget.childProfile` (already resolved) |
| segments | `widget.detail.segmentsForPage(pageId)` (already resolved) |

### 5.3 Lifecycle & wiring
- `initState`: construct `NarrationPlayer`; construct `ScanFlowController` (`childProfileId` + `storyId` are the passed-in resolved values; `onPlayPage` per §5.4); start the camera (reuse `ArStoryScreen._initCamera`, graceful fallback); call `controller.start()` inside `try { … } catch (_) { setState → _error = true } finally { setState → _starting = false }`. `controller.detector` is `null` until `start()` succeeds. **`start()` can throw** — see §7 hawkeye #1.
- `dispose`: dispose `NarrationPlayer` and the camera controller.

### 5.4 `onPlayPage` closure
`ScanFlowController` calls `onPlayPage(pageId)`; `_ScanView` binds it to:
```
(pageId) async {
  if (!mounted) return;                                       // hawkeye #5
  final segments = widget.detail.segmentsForPage(pageId);     // guaranteed loaded (§5.1)
  if (segments.isEmpty) return;
  final n = controller.manifest?.targets
      .firstWhere((t) => t.pageId == pageId).pageNumber;       // safe: handleDetected pre-validates membership
  setState(() => _playingPageNumber = n);
  final lang = widget.childProfile.languageCode ?? 'en';
  await _audio.load(segments, languageCode: lang);
  if (!mounted) return;                                       // hawkeye #5
  unawaited(_audio.play().whenComplete(() {                   // hawkeye #4 + banner clear
    if (mounted) setState(() => _playingPageNumber = null);
  }));
}
```
- **`unawaited(play())`** (hawkeye #4): `handleDetected` records `scan_success` only after `await onPlayPage`. If we awaited `play()` (which resolves at narration end, `narration_player.dart`), the MVP metric would post minutes late and be lost on backgrounding. Returning right after playback *starts* records it promptly.
- **`mounted` guards** (hawkeye #5): `handleDetected` awaits the `startSession` roundtrip before calling `onPlayPage`; if the child backs out during it, running `ref`/`setState` on a disposed state throws. The guards make it a clean no-op.
- **`whenComplete`** clears the "Playing page N…" banner when narration ends (hawkeye minor).

### 5.5 `scan_success` — already wired
The `scan` session (created once, `SessionMode.scan`) and the `scan_success` `recordEvent` are emitted **inside** `ScanFlowController.handleDetected`. Hosting the controller and feeding it a detected `pageId` is all that is required — this slice adds **no** event-posting code of its own. This is the specific gap ("`scan_success` never fires end-to-end") that this slice closes. (Reliability caveat under transient session-start failure: §11.)

### 5.6 Layout (`_ScanView`)
`Scaffold` (app bar "Scan (Preview)"), body is a `Stack`:
- **Background:** camera preview when ready, else the same gradient fallback as `ArStoryScreen`.
- **Body state machine:** `_error` → `ErrorView` ("We couldn't start scanning."); else `_starting` → loading indicator; else `controller.detector != null` → `SimulatedPagePanel(detector: controller.detector! as SimulatedPageDetector)`. The panel is rendered **only** in the last state, so `detector!` is never null-dereferenced. The cast is safe while `nativeImageTrackingWired == false` because `pageDetectorProvider` returns a `SimulatedPageDetector`; guard with an `assert` mirroring the provider's own so a future native detector fails loudly here. (When native tracking lands, this branch becomes the real camera UI, not a panel.)
- **Now-playing banner:** when `_playingPageNumber != null`, a "▶ Playing page N…" line.
- **Empty state:** `SimulatedPagePanel` already renders "Nothing to scan" when `targets` is empty.

## 6. Data flow
```
library card → [Read | Scan] → Scan → /story/:id/scan
  → controller.start() → GET /v1/stories/{id}/image-target-manifest → SimulatedPageDetector
  → tap page (SimulatedPagePanel) → controller.handleDetected(pageId)
  → startSession(mode: scan) [once] → onPlayPage(pageId)
       → NarrationPlayer(segmentsForPage) → assets/sign → GET /assets/{id}   (TTS fallback if no binary)
  → recordEvent(scan_success)
```

## 7. Error handling
| Condition | Behavior |
|---|---|
| Manifest fetch fails | **Corrected (hawkeye #1):** `HttpImageTargetResolver.fetch` only falls back to a *cached* manifest; on the first fetch there is no cache, so it **throws** (and the default base URL is `localhost:8000`, so backend-unreachable is the common case on a real device). `ScanFlowController.start()` does not catch. Therefore `_ScanView` wraps `start()` in `try/catch` (§5.3) and renders an `ErrorView` on failure — the design provides the error state the resolver does not. |
| Story has no targeted pages | `SimulatedPagePanel` renders "Nothing to scan" |
| No camera (simulator/denied) | gradient background fallback (as `ArStoryScreen`) |
| Detected page not in manifest | `handleDetected` no-ops (cannot occur from the panel, which lists only manifest pages) |
| Missing audio binary | existing `NarrationPlayer` TTS fallback |
| Expired / 401 | existing `ApiClient.send()` re-mint |

## 8. Testing (TDD)
- **Reused, already green:** `scan_flow_test` (detect → `scan` session → `scan_success`), `simulated_page_detector_test`, `image_target_resolver_test`, `image_target_manifest_test`.
- **New:** a widget test for `ScanStoryScreen` with fake providers — tapping a page row calls `onPlayPage` (assert a spy/fake audio load) and records `scan_success` via a fake `SessionRepository`. Authored for CI; **not run during development** (per project rule: no widget/e2e/integration runs while developing).
- **New unit test (foundation fix, §11):** `ScanFlowController` with a `SessionRepository` whose first `startSession` throws and second succeeds → first detect posts no `scan_success`, second detect creates a session and posts `scan_success` (proves the failed future is not memoized). Pure Dart, runnable in dev.
- If the `onPlayPage` segment-selection logic warrants isolation, extract a small pure helper and unit-test it directly.

## 9. Units & boundaries
| Unit | Responsibility | Depends on |
|---|---|---|
| `library_screen.dart` (`_StoryCard`) | Book-first Read/Scan chooser (pops sheet before nav) | router |
| `app_router.dart` | `/story/:id/scan` route + `AppRoutes.scan` | `ScanStoryScreen` |
| `ScanStoryScreen` (outer) | Resolve + gate on `childProfile` **and** `detail`; loading/error views | providers |
| `_ScanView` (inner) | Host `ScanFlowController`; camera + panel + now-playing UI; bind `onPlayPage` | `ScanFlowController`, `NarrationPlayer`, `SimulatedPagePanel` |
| `ScanFlowController` (reused) | Orchestrate detect → session → play → event | resolver, detector, session repo |

## 10. Follow-ups (not this slice)
- Native ARKit/ARCore `PageDetector` + on-device validation (flip `nativeImageTrackingWired`); the panel branch in §5.5 is then replaced by the real camera-recognition UI.
- Resume-to-page (gap #12) would enable an alternative "open the player at the detected page" behavior.
- Real page-image binaries so `reference_image_url` is non-null (feeds a real reference-image database).

## 11. Open decision — foundation robustness (hawkeye #3)

`ScanFlowController._ensureSession` (foundation, `scan_flow_controller.dart:81`) does `_sessionFuture ??= startSession(...)`. If `startSession` **throws** (a transient backend blip), the *failed* future is memoized: every later tap awaits the same dead future, which rethrows into the `void onDetected` seam (swallowed as an unhandled async error). One blip → `scan_success` silently never fires again for that screen instance.

The readiness gate in §5.1 removes the **guaranteed** trigger (the `'local'`-profile 404), so the happy/demo path is unaffected. What remains is a genuine-but-transient edge. Two options:

- **(A) Include a minimal foundation fix:** clear `_sessionFuture` when the start fails so the next tap retries. ~3 lines in `_ensureSession` + one unit test (start throws once → next detect creates a session → `scan_success` fires). This touches the "frozen" foundation (§2), but the fix directly serves this slice's goal (reliable `scan_success`). It is the kind of targeted improvement to code-being-worked-in that is in-bounds.
- **(B) Keep the foundation frozen:** ship the gate only, log this as a known follow-up. Simpler diff; leaves the transient-blip edge unfixed.

**Decision (2026-07-09): (A) — include the fix.** Sketch:
```
Future<StorySession> _ensureSession() {
  final existing = _sessionFuture;
  if (existing != null) return existing;
  final f = _sessionRepository.startSession(
      childProfileId: _childProfileId, storyId: _storyId, mode: SessionMode.scan);
  _sessionFuture = f;
  // Clear the memo only if it is still THIS failed future, so a later
  // successful retry is never clobbered. Caller still sees the rethrow.
  f.catchError((Object e) { if (identical(_sessionFuture, f)) _sessionFuture = null; throw e; });
  return f;
}
```
Behavior is unchanged on success; on failure a subsequent tap gets a fresh attempt.
