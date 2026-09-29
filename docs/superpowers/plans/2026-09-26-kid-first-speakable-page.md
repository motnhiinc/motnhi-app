# Kid-first Speakable Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a validated scanned page play with line-by-line highlighting after two child taps from Home.

**Architecture:** Keep AVFoundation/Vision capture in Swift, product state and playback in Flutter, and consent, age screening, approval proofs, and audio generation in the authenticated FastAPI backend. The child scan flow uses a new proof-gated narration API; the existing generic TTS client and curated-story/AR paths remain separate.

**Tech Stack:** Flutter/Riverpod/go_router/just_audio, Swift Vision/Core Image, FastAPI/SQLAlchemy/PostgreSQL/Alembic, OpenAI vision + speech, pytest/flutter_test/XCTest.

**Spec:** `docs/superpowers/specs/2026-09-26-kid-first-speakable-page-design.md`
**Visual target:** [Paper screens](https://app.paper.design/file/01M3DXY6WQN072R1SMD0GH5Z7N/p-1-0)

---

## File boundaries and rollout

1. `backend/app/services/privacy.py`, `backend/app/models/__init__.py`, `backend/app/repositories/privacy.py`, `backend/app/schemas/__init__.py`, `backend/app/routers/privacy.py`, `backend/migrations/versions/0006_page_image_consent.py`: one new independently revocable consent bit, effective server authorization, and policy re-review. Update privacy/profile/TTS test fixtures that hard-code the previous current policy version; keep historical migration/event fixtures intentionally historical.
2. `lib/data/models/privacy_state.dart`, `lib/data/repositories/{privacy_repository,http_privacy_repository}.dart`, `lib/features/privacy/{privacy_providers,privacy_screen,privacy_review_screen,privacy_notice_screen}.dart`, `lib/features/onboarding/onboarding_screen.dart`, `lib/l10n/{app_en,app_vi}.arb`: parent consent choice and disclosure. Regenerate Freezed and localization outputs rather than editing generated Dart.
3. `ios/Runner/ScanAnyPage/{PageScannerViewController,ScanAnyPageBridge,TextObservationSorter}.swift`, `ios/RunnerTests/ScanGeometryTests.swift`, `lib/features/scan_any_page/{native_scan_service,scanned_page}.dart`: capture returns one bounded corrected JPEG plus ordered OCR lines/normalized boxes. `StoryComposerController` also calls `ScanService`; adapt its call site to read `result.joinedText` without changing capture-to-story behavior.
4. `backend/app/services/{page_validation,page_approval}.py`, `backend/app/routers/speakable_page.py`, `backend/app/main.py`, `backend/app/config.py`: bounded image/OCR validation, server-owned age band, signed proof, and complete ordered MP3 bundle. Keep secrets and AI response details out of client errors and logs.
5. `lib/features/scan_any_page/{page_validation_client,line_audio_player,scan_any_page_controller,scan_any_page_screen,page_image_view}.dart`, `lib/core/di.dart`, `lib/features/library/child_home_screen.dart`, `pubspec.yaml`: transport, session lifecycle, line playback, coordinate-highlight view and two-tap UI. Use a new scan-specific cloud client; do not route it through the existing device-TTS fallback.
6. Tests next to each boundary: `backend/tests/test_page_validation.py`, `backend/tests/test_page_audio.py`, `test/{native_scan_service_test,scan_any_page_controller_test,page_image_view_test,line_audio_player_test,privacy_providers_test,widget_test}.dart`, and Swift XCTest. Existing tests referring to the removed OCR editor/AR phases must be replaced with assertions for the new child path, not retained as contradictory expectations.

**Implementation order:** Backend consent → client consent → native scan result → validator/proof → audio bundle → Flutter transport → line player/geometry → coordinator → screens → device QA. Keep incomplete feature surfaces unlinked until all gates work; do not expose a path that can play before validation. Stage only touched files if a later explicit commit request is made; pre-existing modified/untracked workspace files belong to the user.

**Wire contract (one source of truth for Tasks 3–8):** `POST /v1/speakable-page/validate` receives `{"profile_id":"...","image_base64":"<JPEG>","lines":[{"text":"...","left":0.1,"top":0.1,"width":0.8,"height":0.1}]}`; returns `{"status":"approved","proof":"..."}` or `{"status":"blocked"}`. Temporary failure is a safe 503 without a proof. `POST /v1/speakable-page/audio` receives `{"profile_id":"...","proof":"...","lines":["exact first line","exact second line"]}` and returns `application/zip` with `000.mp3`, `001.mp3`, ...; no playable output on any error. Flutter's `ScannedLine` uses the same top-left normalized coordinates; the proof binds only the ordered line texts, not client-supplied age or an edited translation.

### Task 1: Add server-side image-validation consent

**Files:** `backend/migrations/versions/0006_page_image_consent.py`, `backend/app/models/__init__.py`, `backend/app/repositories/privacy.py`, `backend/app/services/privacy.py`, `backend/app/schemas/__init__.py`, `backend/app/routers/privacy.py`, `backend/tests/test_privacy_api.py`, `backend/tests/test_privacy_migration.py`; update current-policy references in `backend/tests/test_{profiles,authored_stories,tts,sessions,privacy_reconcile,child_data_deletion}.py` only when representing current consent.

- [ ] **Write failing backend tests:** Add a `test_page_image_consent_is_separate_and_off_by_default` to `backend/tests/test_privacy_api.py`. GET must return `page_image_validation_enabled=false` and `effective_page_image_validation_enabled=false`; PUT with cloud narration true and image validation false must keep image validation ineffective; PUT with both true under the new policy must enable both. A previously accepted `2026-08-28` record must require review. Add a migration assertion that old rows receive `FALSE`.
- [ ] **Run red:** `pytest tests/test_privacy_api.py tests/test_privacy_migration.py -q` from `backend/`; expect missing response field / missing column assertions.
- [ ] **Implement migration and domain contract:** Add a non-null `page_image_validation_enabled` Boolean with `server_default=sa.false()` and downgrade drop. Set `CURRENT_PRIVACY_POLICY_VERSION = "2026-09-26"`. Add the field to `PrivacySettings`, default creator, `PrivacyUpdateRequest`, `PrivacyStateResponse`, and GET/PUT router mapping. Update `update_settings(..., page_image_validation_enabled: bool)` to record `("page_image_validation", choice)` on new-policy acceptance or choice change. Add:

```python
def upgrade() -> None:
    op.add_column("privacy_settings", sa.Column(
        "page_image_validation_enabled", sa.Boolean(),
        nullable=False, server_default=sa.false(),
    ))

def downgrade() -> None:
    op.drop_column("privacy_settings", "page_image_validation_enabled")

def effective_page_image_validation(settings: PrivacySettings | None) -> bool:
    return bool(settings and settings.accepted_policy_version == CURRENT_PRIVACY_POLICY_VERSION
                and settings.page_image_validation_enabled)

def require_page_reading(settings: PrivacySettings | None) -> None:
    require_cloud_tts(settings)
    if not effective_page_image_validation(settings):
        raise PrivacyError(403, "page_image_validation_disabled")
```

  New `PrivacyUpdateRequest.page_image_validation_enabled` is required (not an implicit `True` default). Update every full-body caller/fixture so a consent mutation cannot silently clear an existing choice.
- [ ] **Run green:** `pytest tests/test_privacy_api.py tests/test_privacy_migration.py tests/test_tts.py tests/test_profiles.py tests/test_sessions.py -q`; expect pass. Run `alembic upgrade head` against the development database; inspect that old settings have the new bit `false` and current-policy review is required. Do not edit the existing 0005 migration.

### Task 2: Thread the parent choice through Flutter and localization

**Files:** `lib/data/models/privacy_state.dart`, `lib/data/repositories/{privacy_repository,http_privacy_repository}.dart`, `lib/features/privacy/{privacy_providers,privacy_screen,privacy_review_screen,privacy_notice_screen}.dart`, `lib/features/onboarding/onboarding_screen.dart`, `lib/l10n/{app_en,app_vi}.arb`, `test/{privacy_providers_test,privacy_notifier_test,privacy_localization_test,http_repositories_test}.dart` (use actual existing test filenames under `test/`).

- [ ] **Write red tests:** Assert JSON parsing of both new flags, a full PUT body containing `page_image_validation_enabled`, and that changing progress/cloud narration preserves the current image choice. Verify onboarding and re-review start with the image option unchecked; gated settings can turn it off; text states that the page image and recognized text go to the backend and AI provider.
- [ ] **Run red:** `flutter test test/privacy_providers_test.dart test/privacy_localization_test.dart test/http_repositories_test.dart`; expect missing fields/methods.
- [ ] **Implement the contract:** Add `@Default(false) bool pageImageValidationEnabled` and `@Default(false) bool effectivePageImageValidationEnabled` in `PrivacyState`. Extend `PrivacyRepository.updatePrivacy` and `HttpPrivacyRepository.updatePrivacy` with required `pageImageValidationEnabled`, serialized as `page_image_validation_enabled`. Extend `PrivacyNotifier.updatePrivacy` and `_updateCurrent`, forwarding `pageImageValidationEnabled ?? current.pageImageValidationEnabled`; add `setPageImageValidation(bool enabled)`. Add `effectivePageImageValidationProvider` using fresh `privacyProvider`, never the display cache. Add the third optional switch to onboarding/review/settings and disclosure to `privacy_notice_screen.dart`; keep cloud TTS and image choices separate. Add localized EN/VI titles, explanations, and child states to both `.arb` files, then run `flutter gen-l10n` and `dart run build_runner build --delete-conflicting-outputs`.

```dart
final effectivePageImageValidationProvider = Provider<bool>((ref) =>
    ref.watch(privacyProvider).value?.effectivePageImageValidationEnabled ?? false);

Future<void> setPageImageValidation(bool enabled) =>
    _updateCurrent(pageImageValidationEnabled: enabled);

// In every full-body PUT, including onboarding/re-review and other toggle edits:
'page_image_validation_enabled': pageImageValidationEnabled,
```
- [ ] **Run green:** Repeat the targeted Flutter tests, then `flutter analyze`; expect no analyzer errors. Review the generated Freezed/JSON keys rather than hand-editing generated files.

### Task 3: Return a corrected image with OCR line geometry

**Files:** Create `lib/features/scan_any_page/scanned_page.dart`; modify `lib/features/scan_any_page/native_scan_service.dart`, `ios/Runner/ScanAnyPage/{PageScannerViewController,ScanAnyPageBridge,TextObservationSorter}.swift`, `ios/RunnerTests/ScanGeometryTests.swift`, `lib/features/story_composer/story_composer_controller.dart`, `test/native_scan_service_test.dart`, `test/story_composer_controller_test.dart`.

- [ ] **Write red tests:** A Swift geometry test with a Vision bottom-left box `(x: .1, y: .7, w: .8, h: .2)` must produce display top-left `(left: .1, top: .1, width: .8, height: .2)`; invalid/out-of-bounds boxes fail. Flutter channel test parses `imageBytes`, `width`, `height`, `lines: [{text,left,top,width,height}]` and rejects missing bytes, empty lines, >40 lines, >4,000 total runes, >8 MiB, >3,000-pixel long edge. Capture-to-story still receives joined lines.
- [ ] **Run red:** `flutter test test/native_scan_service_test.dart test/story_composer_controller_test.dart` and `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,id=D910390E-59AC-4B1F-BA75-DE0EE4B88A00' test`; expect new contract/geometry assertions to fail. If that simulator is unavailable later, replace only the destination ID with an available iPad simulator from `xcrun simctl list devices available`.
- [ ] **Implement a typed result:**

```dart
class ScannedLine {
  const ScannedLine(this.text, this.left, this.top, this.width, this.height);
  final String text;
  final double left, top, width, height; // top-left normalized
}
class ScannedPage {
  const ScannedPage(this.jpegBytes, this.width, this.height, this.lines);
  final Uint8List jpegBytes;
  final int width, height;
  final List<ScannedLine> lines;
  String get joinedText => lines.map((line) => line.text).join('\n');
}
```

  Change `ScanService.scanAndRecognize()` to return `Future<ScannedPage>`. Extract `TextObservationSorter.ordered(_:) -> [RecognizedLine]` from its existing `join` implementation and make `join` call `ordered(...).map(\.text).joined(separator: "\n")`, so the same ordering drives both features. In Swift, after perspective correction, resize preserving aspect ratio, encode JPEG, reject if still over 8 MiB, and return ordered OCR observations **with their individual boxes**, converting Vision `top = 1 - maxY`. Bridge the bytes via `FlutterStandardTypedData(bytes: jpeg)` and image dimensions. Keep one-shot cancellation/error behavior. Have story composer use `page.joinedText` and discard image after its existing flow.
- [ ] **Run green:** Repeat both exact commands above and `flutter analyze`; expect pass. On physical iPad, scan portrait and landscape samples and verify the JPEG and line rectangles refer to the same corrected image, not preview coordinates.

### Task 4: Build fail-closed AI validation and signed approval

**Files:** Create `backend/app/services/page_validation.py`, `backend/app/services/page_approval.py`, `backend/app/routers/speakable_page.py`, `backend/tests/test_page_validation.py`; modify `backend/app/{config,main}.py` and `backend/.env.example`.

- [ ] **Write red tests:** Authenticate a device, create an owned child profile and enable both consents. Mock validation to approve an English, Vietnamese, and mixed-language page. Assert `POST /v1/speakable-page/validate` with base64 JPEG + ordered lines/boxes returns an approval proof only for the approved case. Reject missing consent/profile ownership, MIME/signature/size/dimension/box errors before provider construction. Assert mismatch, unsuitable, uncertain, malformed provider output and provider timeout never return a proof. Response errors must not contain provider text or OCR content.
- [ ] **Run red:** `pytest tests/test_page_validation.py -q` from `backend/`; expect missing route.
- [ ] **Implement narrow schemas and service:** `PageLine(text, left, top, width, height)` validates finite top-left normalized boxes within `[0,1]`; `ValidatePageRequest(profile_id, image_base64, lines)` checks 1–40 lines and <=4,000 Unicode characters. Decode JPEG (check SOI and actual dimensions with Pillow; add `pillow>=11.0` to `backend/pyproject.toml` and cap decompressed pixels), reject >8 MiB and >3,000 pixels before OpenAI. Look up `profiles.get_owned(db,user.id,profile_id)`; call `require_page_reading` first. The OpenAI multimodal service sends image+OCR lines+server-owned age band and requests an exact schema with `text_matches: bool`, `age_suitable: bool`, `certain: bool`; accept **only** three explicit `true` booleans, no rewritten lines. Configure `OPENAI_PAGE_VALIDATION_MODEL=gpt-4o-mini` and `OPENAI_PAGE_VALIDATION_TIMEOUT_SECONDS=30` in `backend/app/config.py`/`.env.example`, with no automatic retry. Keep result mapping `approved | blocked | temporary_error` and `Cache-Control: no-store`.

```python
class ValidationVerdict(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text_matches: bool
    age_suitable: bool
    certain: bool

def approved(verdict: ValidationVerdict) -> bool:
    return verdict.text_matches is True and verdict.age_suitable is True and verdict.certain is True
```
- [ ] **Implement proof with no DB row:** In `page_approval.py`, canonicalize ordered lines as UTF-8 compact JSON (preserve text exactly), SHA-256 hash them, and sign a JWT with `sub=user.id`, `profile_id`, `lines_sha256`, `scope="page_audio"`, `iat`, and `exp=iat+10 minutes`, using `settings.jwt_secret`/`settings.jwt_algorithm`. Verification rejects missing/wrong scope, wrong user/profile, expired proof, or changed lines; never include raw page text/image in the token. Add tests for each failure. Register the router in `backend/app/main.py`.

```python
def line_digest(lines: list[str]) -> str:
    payload = json.dumps(lines, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()

def issue_approval(user_id: str, profile_id: str, lines: list[str]) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode({"sub": user_id, "profile_id": profile_id,
                       "lines_sha256": line_digest(lines), "scope": "page_audio",
                       "iat": now, "exp": now + timedelta(minutes=10)},
                      settings.jwt_secret, algorithm=settings.jwt_algorithm)
```
- [ ] **Run green:** `pytest tests/test_page_validation.py -q`; expect approved-only proofs and zero provider calls on invalid input. Also run `pytest tests/test_privacy_api.py tests/test_tts.py -q`.
- [ ] **Development configuration:** Ensure the backend's OpenAI project key can call the selected vision-capable model as well as the existing speech endpoint; the current demo key was scoped only to speech. Keep the key in untracked `.env`, never in the app. Smoke-test the vision call with a harmless fixture image before physical-device QA.

### Task 5: Generate complete line-aligned audio through the proof gate

**Files:** Modify `backend/app/routers/speakable_page.py`, `backend/app/services/page_approval.py`, `backend/app/services/tts.py`; create `backend/tests/test_page_audio.py`.

- [ ] **Write red tests:** `POST /v1/speakable-page/audio` receives `{profile_id, proof, lines}`. Wrong/expired proof, changed line order/text, revoked consent, or foreign profile must make zero TTS calls. On approval, fake TTS records `lines.map(text)` in order and response ZIP contains exactly `000.mp3...N.mp3`. If any line fails or returns empty bytes, return an error with no partial bundle. Check `Cache-Control: no-store` and no response text contains original page words.
- [ ] **Run red:** `pytest tests/test_page_audio.py -q`; expect missing endpoint.
- [ ] **Implement:** Recheck both current consents and owned profile, verify proof against submitted exact lines, generate one MP3 per line via the existing `OpenAiTtsService.generate`, write each into an in-memory `zipfile.ZipFile` as zero-padded ordinal filename, and return `application/zip` only once all entries succeed. Cap individual MP3s at 2 MiB and whole ZIP at 32 MiB; reject/fail rather than serving partial audio. Do not persist audio or request data. Keep generic `/v1/tts` unchanged for authored stories.

```python
buffer = BytesIO()
with ZipFile(buffer, "w", compression=ZIP_STORED) as archive:
    for index, text in enumerate(lines):
        audio = service.generate(text)
        if not audio or len(audio) > 2 * 1024 * 1024:
            raise HTTPException(status_code=502, detail="narration generation failed")
        archive.writestr(f"{index:03d}.mp3", audio)
if buffer.tell() > 32 * 1024 * 1024:
    raise HTTPException(status_code=502, detail="narration generation failed")
return Response(buffer.getvalue(), media_type="application/zip",
                headers={"Cache-Control": "no-store"})
```
- [ ] **Run green:** `pytest tests/test_page_validation.py tests/test_page_audio.py tests/test_tts.py -q`; expect pass. Record generation latency on representative 3-, 10-, and 20-line pages; do not claim faster time-to-sound without measurement.

### Task 6: Implement client transport and temporary bundle ownership

**Files:** Create `lib/features/scan_any_page/page_validation_client.dart`; modify `lib/core/di.dart`, `pubspec.yaml`; create `test/page_validation_client_test.dart`.

- [ ] **Write red tests:** Mock Dio to assert that no request is sent without effective fresh consent and profile; JSON base64 encodes exact JPEG and ordered lines. Approved validation sends proof to `/audio`; rejected verdict calls no audio endpoint. Decode a ZIP with ordinal MP3 names into isolated temporary files; fail and delete all files for missing/duplicate/out-of-order/empty entries or wrong content type. Dispose removes owned image/clip files and late responses cannot recreate them.
- [ ] **Run red:** `flutter test test/page_validation_client_test.dart`; expect missing client.
- [ ] **Implement:** Add `archive: ^4.0.0` to `pubspec.yaml` and run `flutter pub get`. Define `PageValidationClient.validate(ScannedPage page, String profileId)` returning an approved proof or blocked/error result and `prepareAudio(proof, profileId, lines)` returning ordered files. Use `ApiClient.send` for authenticated POST, `dio` `ResponseType.bytes` for ZIP, and `ZipDecoder` from `archive`; require `application/zip` and exactly matching zero-padded ordinal filenames. Write to per-flow temporary directory and delete it via client `dispose`; never share `HttpTtsClient`'s single-clip filename or device-TTS fallback. Register the client as a `Provider.autoDispose.family` and with `liveResourceDisposersProvider` in `lib/core/di.dart`.
- [ ] **Run green:** `flutter test test/page_validation_client_test.dart && flutter analyze`; expect pass. Verify an HTTP 403 after consent revocation is surfaced as missing consent, not as a playable ready state.

### Task 7: Play clips and map each line to the photograph

**Files:** Create `lib/features/scan_any_page/{line_audio_player,page_image_view}.dart`, `test/{line_audio_player,page_image_view}_test.dart`; use `just_audio` already in `pubspec.yaml`.

- [ ] **Write red tests:** A 2-line fake player marks line 0 when its clip starts, line 1 only after clip 0 completes, holds index during pause, and resets to 0 on replay. For a 440×585 image fitted inside 704×650, compute the rendered image rect and verify top-left normalized `(0.1,0.1,0.8,0.2)` maps to the corresponding offset/size in that rect (not the entire container). Invalid/overflow boxes fail rather than painting outside the image.
- [ ] **Run red:** `flutter test test/line_audio_player_test.dart test/page_image_view_test.dart`; expect missing classes.
- [ ] **Implement:** Use a `just_audio` playlist of the exact ordered clip files and subscribe to `currentIndexStream`/player state; expose `ValueListenable<int>` for the current line and `play/pause/resume/replay/stop/dispose`. In `PageImageView`, decode image dimensions from `ScannedPage`, compute `scale=min(viewWidth/imageWidth, viewHeight/imageHeight)`, `rect=(left=(viewWidth-scaledWidth)/2, top=(viewHeight-scaledHeight)/2, scaledWidth, scaledHeight)`, and paint a translucent gold overlay at `rect.left + line.left*rect.width`, `rect.top + line.top*rect.height` with width/height scaled by the same rect. Render the JPEG as the image, not OCR text. Use clip-start events, not estimated speech duration, as line transition source.

```dart
Rect imageRect(Size view, ScannedPage page) {
  final scale = math.min(view.width / page.width, view.height / page.height);
  final width = page.width * scale, height = page.height * scale;
  return Rect.fromLTWH((view.width - width) / 2, (view.height - height) / 2,
      width, height);
}

Rect lineRect(Rect image, ScannedLine line) => Rect.fromLTWH(
    image.left + line.left * image.width,
    image.top + line.top * image.height,
    line.width * image.width, line.height * image.height);
```
- [ ] **Run green:** Repeat the two targeted Flutter tests; `flutter analyze`; expect pass. On device, check portrait/landscape page alignment and long lines with diacritics.

### Task 8: Replace OCR editor/AR phase with a safe scan coordinator

**Files:** Modify `lib/features/scan_any_page/scan_any_page_controller.dart`, `lib/core/di.dart`, `test/scan_any_page_controller_test.dart`; keep `lib/features/scan_any_page/native_character_reader.dart` for other/legacy usages, not the child scan dependency.

- [ ] **Write red controller tests:** With fakes for scanner, validator/audio client and fresh-privacy checker: `startScan` moves `scanning → preparing → ready` only after approval plus all clips; a blocked result has no clips/Listen; `listen` from ready calls line player only after fresh consent; scanner cancellation is idle; late validation/audio completion after rescan/reset/dispose is ignored and cleaned; revocation or privacy-refresh failure while playing stops and clears session. Retry technical errors while local capture/proof is valid; no child bypass of blocked content.
- [ ] **Run red:** `flutter test test/scan_any_page_controller_test.dart`; expect old phase assumptions and/or missing methods.
- [ ] **Implement a focused state machine:** `ScanAnyPagePhase {idle, scanning, preparing, ready, playing, paused, completed, blocked, failure, setupRequired}`. State contains `ScannedPage? page`, `List<File> clips`, `String? proof`, `int activeLineIndex`, and typed failure code. `startScan` checks fresh consent/profile **before** camera/upload; passes result through validator and audio client; only sets ready after clip count equals line count and every box is valid. `listen`, `pause`, `resume`, `replay`, `reset` delegate to `LineAudioPlayer`. Increment generation before every reset/rescan and register disposal for image/audio. Poll fresh consent at most 15 seconds apart while active and refresh on app resume; on failure/revocation stop and wipe. Remove `confirmText`, `retryTts`, and `openCharacterReader` from this child coordinator and update its tests instead of preserving the six-tap route behind an invisible branch.
- [ ] **Run green:** `flutter test test/scan_any_page_controller_test.dart && flutter analyze`; expect pass. Ensure `StoryComposerController` and curated story reader tests still pass.

### Task 9: Build the child-facing screens and two-tap route

**Files:** Modify `lib/features/library/child_home_screen.dart`, `lib/features/scan_any_page/scan_any_page_screen.dart`, `lib/core/di.dart`, `lib/l10n/{app_en,app_vi}.arb`, `test/widget_test.dart`; refer to the Paper screens linked above.

- [ ] **Write red widget tests:** Home shows a dominant **Scan a page** button; one tap enters the native scanner without a second scan-entry action. With fakes, auto-capture transitions to **Making your page ready**, then a validated page with one **Listen** button; one more tap starts playback and the first line highlights. Blocked/uncertain content never displays page text/image or Listen. Missing consent offers a gated parent-setup action. Verify 44px+ touch targets and both EN/VI strings.
- [ ] **Run red:** `flutter test test/widget_test.dart`; expect old home/scan UI assertions or missing widgets.
- [ ] **Implement:** Promote a `PressablePillButton(label: s.scanPrimaryCta, onPressed: () => context.push(AppRoutes.scanAnyPage))` to the home hero. On `ScanAnyPageScreen` entry, start scan once after first frame when consent is effective; do not require a second button. Render distinct `scanning`, `preparing`, `ready`, `playing/paused/completed`, `blocked`, `failure`, `setupRequired` widgets with `PageImageView` only for approved phases. Ready uses large Listen, playing uses Pause/Resume/Replay, blocked uses only neutral copy and Scan another page. Remove text-edit and Place character actions from this route; keep `AppRoutes.scanAnyPage` and library/curated routes stable. Add localized screen/error strings to both ARB files and regenerate `flutter gen-l10n`.
- [ ] **Run green:** `flutter test test/widget_test.dart test/scan_any_page_controller_test.dart test/page_image_view_test.dart && flutter analyze`; expect pass. Compare on-device home, scanner, waiting, ready, playing, and blocked screens against Paper at iPad portrait size.

### Task 10: End-to-end hardening and release checks

**Files:** Relevant changed tests and `docs/superpowers/specs/2026-09-26-kid-first-speakable-page-design.md` only if device findings revise an approved requirement; no unrelated refactor.

- [ ] **Backend:** Run `pytest -q` from `backend/` with the test PostgreSQL service available, plus `alembic upgrade head` on a database containing old consent. Validate no new image/audio DB rows and no image/OCR/AI body in app logs. Confirm unavailable provider and stale-policy sessions fail closed.
- [ ] **Flutter/native:** Run `flutter test`, `flutter analyze`, and `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,id=D910390E-59AC-4B1F-BA75-DE0EE4B88A00' test`, then a physical iPad walkthrough with English, Vietnamese, mixed-language, low light/glare, incorrect OCR, unsuitable/borderline page, provider/TTS outages, app resume, rescan, and consent revocation. Confirm the scanner and page overlay use identical corrected-image coordinates.
- [ ] **Measure:** From child Home with setup complete, count **two taps to sound** on an approved page. Record median and slow-case wall-clock Home→sound time for 3-, 10-, and 20-line pages. Check cleanup after each failure/exit and that rejected pages never create audio. Record observations in the plan's verification notes during execution; do not convert interaction improvement into a speed claim without data.

## Plan self-review checklist

- Consent enforced before image upload and at both backend endpoints; distinct bit and policy review included.
- All success paths require approved image/OCR + age verdict, bound proof, full audio bundle, and a fresh permission check.
- All failure paths lack Listen; blocked pages do not display rejected content; temporary files are cleaned and stale operations cannot restore ready state.
- The only child actions for the happy path are Home Scan and Ready Listen; line playback and overlay share OCR ordering/coordinates.
- Current generic TTS, authored stories, story composer and curated AR keep their own paths and regression tests.
