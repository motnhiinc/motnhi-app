# Scan Any Page Voice + AR Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an iPad demo that automatically captures one large-text English/Vietnamese page, confirms OCR text, generates one OpenAI narration clip through the local backend, and places one speaking 3D character on a table.

**Architecture:** Flutter owns the product state, editable OCR review, authenticated TTS request, temporary audio, and navigation. Two narrow Swift method-channel bridges own hardware-specific work: AVFoundation/Vision/Core Image capture and OCR, then RealityKit plane placement and character playback. FastAPI validates confirmed text and proxies one request to OpenAI without persisting text or audio.

**Tech Stack:** Flutter 3.38, Riverpod 3, go_router, Dio, Swift, UIKit, AVFoundation, Vision, Core Image, ARKit, RealityKit, AVFoundation audio, FastAPI, official OpenAI Python SDK, pytest, flutter_test, XCTest.

**Design:** `docs/superpowers/specs/2026-08-14-scan-any-page-voice-ar-demo-design.md`

---

## File Map

### Backend

- Create `backend/app/services/tts.py`: OpenAI speech adapter, typed upstream failure, and injectable service dependency.
- Create `backend/app/routers/tts.py`: authenticated `/v1/tts` validation and MP3 response.
- Create `backend/tests/test_tts.py`: endpoint contract, one-request mixed-language behavior, and upstream error mapping.
- Modify `backend/app/config.py`: secret, model, voice, and timeout settings.
- Modify `backend/app/main.py`: register the TTS router.
- Modify `backend/pyproject.toml`: official OpenAI SDK dependency.
- Modify `backend/.env.example`: non-secret TTS configuration and an intentionally empty key field.

### Flutter

- Create `lib/features/scan_any_page/native_scan_service.dart`: typed Dart wrapper for the scan/OCR method channel.
- Create `lib/features/scan_any_page/native_character_reader.dart`: typed Dart wrapper for the AR method channel.
- Create `lib/features/scan_any_page/tts_client.dart`: authenticated MP3 request and temporary-file lifecycle.
- Create `lib/features/scan_any_page/scan_any_page_controller.dart`: explicit state machine and retry/reset rules.
- Create `lib/features/scan_any_page/scan_any_page_screen.dart`: entry, OCR review, progress, retry, and AR launch UI.
- Create `test/native_scan_service_test.dart`: scan channel mapping tests.
- Create `test/native_character_reader_test.dart`: AR channel mapping tests.
- Create `test/tts_client_test.dart`: request validation, response validation, and file cleanup tests.
- Create `test/scan_any_page_controller_test.dart`: state and retention tests.
- Modify `lib/core/di.dart`: providers for new services and controller dependencies.
- Modify `lib/core/router/app_router.dart`: independent `/scan-any-page` route.
- Modify `lib/features/library/library_screen.dart`: visible entry action without changing story-card actions.

### iOS

- Create `ios/Runner/ScanAnyPage/ScanGeometry.swift`: normalized quadrilateral and stability heuristic.
- Create `ios/Runner/ScanAnyPage/TextObservationSorter.swift`: deterministic OCR reading order.
- Create `ios/Runner/ScanAnyPage/PageScannerViewController.swift`: camera preview, rectangle detection, quality/stability gate, still capture, perspective correction, and OCR.
- Create `ios/Runner/ScanAnyPage/ScanAnyPageBridge.swift`: scanner method-channel presenter and typed result mapping.
- Create `ios/Runner/CharacterReader/CharacterReaderViewController.swift`: RealityKit surface detection, placement, model, player, and speaking indicator.
- Create `ios/Runner/CharacterReader/CharacterReaderBridge.swift`: AR method-channel presenter and typed result mapping.
- Add `ios/Runner/CharacterReader/toy_drummer.usdz`: local prototype-only Apple AR Quick Look sample.
- Create `ios/Runner/CharacterReader/ASSET_LICENSE.md`: exact source URL, retrieval date, prototype-only restriction, and replacement gate.
- Create `ios/RunnerTests/ScanGeometryTests.swift`: rectangle stability tests.
- Create `ios/RunnerTests/TextObservationSorterTests.swift`: OCR ordering tests.
- Modify `ios/Runner/AppDelegate.swift`: register both native bridges.
- Modify `ios/Runner/Info.plist`: accurate camera usage text.
- Modify `ios/Runner.xcodeproj/project.pbxproj`: source, test, and resource membership.

---

### Task 1: Backend TTS Contract and Configuration

**Files:**
- Create: `backend/tests/test_tts.py`
- Create: `backend/app/services/tts.py`
- Create: `backend/app/routers/tts.py`
- Modify: `backend/app/config.py:4-17`
- Modify: `backend/app/main.py:1-11`
- Modify: `backend/pyproject.toml:6-15`
- Modify: `backend/.env.example:1-8`

- [ ] **Step 1: Add failing endpoint tests**

Create `backend/tests/test_tts.py` with an authenticated helper and a fake injectable service:

```python
from dataclasses import dataclass

from app.main import app
from app.routers.tts import get_tts_service
from app.services.tts import TtsUpstreamError


def _auth(client):
    token = client.post("/v1/auth/device", json={"device_id": "tts-device"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


@dataclass
class FakeTtsService:
    audio: bytes = b"ID3demo"
    error: Exception | None = None
    calls: list[str] | None = None

    def __post_init__(self):
        self.calls = []

    def generate(self, text: str) -> bytes:
        self.calls.append(text)
        if self.error is not None:
            raise self.error
        return self.audio


def test_tts_requires_auth(client):
    assert client.post("/v1/tts", json={"text": "Hello"}).status_code == 401


def test_tts_rejects_empty_and_over_limit_without_upstream_call(client):
    fake = FakeTtsService()
    app.dependency_overrides[get_tts_service] = lambda: fake
    headers = _auth(client)
    try:
        assert client.post("/v1/tts", json={"text": "   "}, headers=headers).status_code == 422
        assert client.post("/v1/tts", json={"text": "x" * 4001}, headers=headers).status_code == 422
        assert fake.calls == []
    finally:
        app.dependency_overrides.pop(get_tts_service, None)


def test_tts_forwards_mixed_text_once_and_returns_non_cacheable_mp3(client):
    fake = FakeTtsService()
    app.dependency_overrides[get_tts_service] = lambda: fake
    text = "The moon is bright. Một đêm thật đẹp."
    try:
        response = client.post("/v1/tts", json={"text": text}, headers=_auth(client))
        assert response.status_code == 200
        assert response.content == b"ID3demo"
        assert response.headers["content-type"] == "audio/mpeg"
        assert response.headers["cache-control"] == "no-store"
        assert fake.calls == [text]
    finally:
        app.dependency_overrides.pop(get_tts_service, None)


def test_tts_maps_upstream_failure_without_leaking_details(client):
    fake = FakeTtsService(error=TtsUpstreamError("secret upstream detail"))
    app.dependency_overrides[get_tts_service] = lambda: fake
    try:
        response = client.post("/v1/tts", json={"text": "Hello"}, headers=_auth(client))
        assert response.status_code == 502
        assert response.json() == {"detail": "narration generation failed"}
        assert "secret upstream detail" not in response.text
    finally:
        app.dependency_overrides.pop(get_tts_service, None)
```

- [ ] **Step 2: Run tests to verify the contract is missing**

Run from `backend/`:

```bash
uv run pytest tests/test_tts.py -v
```

Expected: collection fails because `app.routers.tts` and `app.services.tts` do not exist.

- [ ] **Step 3: Add settings and the OpenAI SDK**

Add to `Settings` in `backend/app/config.py`:

```python
openai_api_key: str = ""
openai_tts_model: str = "gpt-4o-mini-tts"
openai_tts_voice: str = "coral"
openai_tts_timeout_seconds: float = 30.0
```

Add `"openai>=1.0",` to `backend/pyproject.toml`. Add to `backend/.env.example`:

```dotenv
# Restricted project key: allow Request only for /v1/audio/speech.
OPENAI_API_KEY=
OPENAI_TTS_MODEL=gpt-4o-mini-tts
OPENAI_TTS_VOICE=coral
OPENAI_TTS_TIMEOUT_SECONDS=30
```

Run from `backend/`:

```bash
uv sync
```

Expected: dependency resolution succeeds and `uv.lock` records the OpenAI SDK.

- [ ] **Step 4: Implement the service and endpoint**

Create `backend/app/services/tts.py`:

```python
from functools import lru_cache

from openai import OpenAI

from app.config import settings


class TtsUpstreamError(RuntimeError):
    pass


class OpenAiTtsService:
    def __init__(self) -> None:
        if not settings.openai_api_key:
            raise TtsUpstreamError("OPENAI_API_KEY is not configured")
        self._client = OpenAI(
            api_key=settings.openai_api_key,
            timeout=settings.openai_tts_timeout_seconds,
            max_retries=0,
        )

    def generate(self, text: str) -> bytes:
        try:
            response = self._client.audio.speech.create(
                model=settings.openai_tts_model,
                voice=settings.openai_tts_voice,
                input=text,
                response_format="mp3",
            )
            return response.content
        except Exception as error:
            raise TtsUpstreamError("OpenAI speech request failed") from error


@lru_cache
def get_openai_tts_service() -> OpenAiTtsService:
    return OpenAiTtsService()
```

Create `backend/app/routers/tts.py`:

```python
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, StringConstraints

from app.auth import get_current_user
from app.models import User
from app.services.tts import OpenAiTtsService, TtsUpstreamError, get_openai_tts_service

router = APIRouter(prefix="/v1/tts", tags=["tts"])
ConfirmedText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4000)]


class TtsRequest(BaseModel):
    text: ConfirmedText


def get_tts_service() -> OpenAiTtsService:
    return get_openai_tts_service()


@router.post("")
def generate_tts(
    request: TtsRequest,
    _: User = Depends(get_current_user),
    service: OpenAiTtsService = Depends(get_tts_service),
) -> Response:
    try:
        audio = service.generate(request.text)
    except TtsUpstreamError as error:
        raise HTTPException(status_code=502, detail="narration generation failed") from error
    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={"Cache-Control": "no-store"},
    )
```

Import `tts` and call `app.include_router(tts.router)` in `backend/app/main.py`.

- [ ] **Step 5: Run the focused backend tests**

Run from `backend/`:

```bash
uv run pytest tests/test_tts.py -v
```

Expected: all tests pass and no real OpenAI request occurs.

- [ ] **Step 6: Run backend regression tests**

Run from `backend/`:

```bash
uv run pytest -v
```

Expected: all backend tests pass.

- [ ] **Step 7: Commit the backend slice**

```bash
git add backend/.env.example backend/app/config.py backend/app/main.py backend/app/routers/tts.py backend/app/services/tts.py backend/pyproject.toml backend/uv.lock backend/tests/test_tts.py
git commit -m "feat(tts): add authenticated OpenAI narration endpoint"
```

### Task 2: Flutter Native Bridge Contracts

**Files:**
- Create: `lib/features/scan_any_page/native_scan_service.dart`
- Create: `lib/features/scan_any_page/native_character_reader.dart`
- Create: `test/native_scan_service_test.dart`
- Create: `test/native_character_reader_test.dart`

- [ ] **Step 1: Write failing method-channel tests**

Test these exact contracts with Flutter's binary messenger:

```dart
const scanChannelName = 'storybook_ar/scan_any_page';
const readerChannelName = 'storybook_ar/character_reader';
```

`test/native_scan_service_test.dart` must verify:

```dart
test('returns recognized text', () async {
  messenger.setMockMethodCallHandler(channel, (call) async {
    expect(call.method, 'scanAndRecognize');
    return {'text': 'Hello. Một đêm đẹp.'};
  });
  expect(await NativeScanService().scanAndRecognize(), 'Hello. Một đêm đẹp.');
});

test('maps cancelled platform error', () async {
  messenger.setMockMethodCallHandler(channel, (_) async {
    throw PlatformException(code: 'cancelled');
  });
  expect(
    NativeScanService().scanAndRecognize,
    throwsA(isA<ScanCancelled>()),
  );
});
```

`test/native_character_reader_test.dart` must verify `open(audioFilePath)` invokes `openCharacterReader` with `{'audioFilePath': path}`, returns normally for `completed`, maps `cancelled` to `CharacterReaderCancelled`, and maps other platform codes to `CharacterReaderFailure(code)`.

- [ ] **Step 2: Run tests to verify missing types**

```bash
flutter test test/native_scan_service_test.dart test/native_character_reader_test.dart
```

Expected: compilation fails because the service classes do not exist.

- [ ] **Step 3: Implement minimal typed wrappers**

Create `native_scan_service.dart` with:

```dart
import 'package:flutter/services.dart';

abstract interface class ScanService {
  Future<String> scanAndRecognize();
}

final class ScanCancelled implements Exception {}

final class ScanFailure implements Exception {
  const ScanFailure(this.code);
  final String code;
}

final class NativeScanService implements ScanService {
  NativeScanService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('storybook_ar/scan_any_page');

  final MethodChannel _channel;

  @override
  Future<String> scanAndRecognize() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('scanAndRecognize');
      final text = result?['text'] as String?;
      if (text == null || text.trim().isEmpty) throw const ScanFailure('no_text');
      return text;
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') throw ScanCancelled();
      throw ScanFailure(error.code);
    }
  }
}
```

Create `native_character_reader.dart` with the equivalent `CharacterReader`, `NativeCharacterReader`, `CharacterReaderCancelled`, and `CharacterReaderFailure` types. The method returns only after native reports completion/cancellation.

- [ ] **Step 4: Run bridge tests**

```bash
flutter test test/native_scan_service_test.dart test/native_character_reader_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit bridge contracts**

```bash
git add lib/features/scan_any_page/native_scan_service.dart lib/features/scan_any_page/native_character_reader.dart test/native_scan_service_test.dart test/native_character_reader_test.dart
git commit -m "feat(scan-any): define native scanner and AR contracts"
```

### Task 3: Native Auto-Capture and Bilingual OCR

**Files:**
- Create: `ios/Runner/ScanAnyPage/ScanGeometry.swift`
- Create: `ios/Runner/ScanAnyPage/TextObservationSorter.swift`
- Create: `ios/Runner/ScanAnyPage/PageScannerViewController.swift`
- Create: `ios/Runner/ScanAnyPage/ScanAnyPageBridge.swift`
- Create: `ios/RunnerTests/ScanGeometryTests.swift`
- Create: `ios/RunnerTests/TextObservationSorterTests.swift`
- Modify: `ios/Runner/AppDelegate.swift:1-13`
- Modify: `ios/Runner/Info.plist:15-16`
- Modify: `ios/Runner.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write native tests for stability and reading order**

Define `NormalizedQuad` with `topLeft`, `topRight`, `bottomLeft`, `bottomRight`, computed `area`, and `maximumCornerDistance(to:)`. Define `RectangleStabilityTracker(requiredStableFrames:tolerance:minimumArea:)` with `observe(_:, qualityAcceptable:) -> Bool` and `reset()`.

Tests in `ScanGeometryTests.swift` must cover:

```swift
func testCapturesOnlyAfterRequiredStableFrames() {
  var tracker = RectangleStabilityTracker(requiredStableFrames: 3, tolerance: 0.02, minimumArea: 0.35)
  let quad = NormalizedQuad.unitInset(0.1)
  XCTAssertFalse(tracker.observe(quad, qualityAcceptable: true))
  XCTAssertFalse(tracker.observe(quad, qualityAcceptable: true))
  XCTAssertTrue(tracker.observe(quad, qualityAcceptable: true))
}

func testMovementAndBadQualityResetStability() { /* assert counter restarts */ }
func testSmallRectangleNeverCaptures() { /* area below 0.35 */ }
```

Define `RecognizedLine(text:boundingBox:)` and `TextObservationSorter.join(_:)`. Tests must assert top-to-bottom ordering, left-to-right ordering for lines sharing a row, newline joining, and preservation of Vietnamese diacritics.

- [ ] **Step 2: Add test/source groups and run native tests red**

Add the new Swift files to the Runner/RunnerTests groups and the appropriate Sources phases in `project.pbxproj`.

Run:

```bash
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'
```

Expected: tests fail because `NormalizedQuad`, `RectangleStabilityTracker`, and `TextObservationSorter` are undefined.

- [ ] **Step 3: Implement pure geometry and OCR ordering helpers**

Implement normalized distance with `hypot`, polygon area with the shoelace formula, and stability as consecutive observations. `TextObservationSorter.join` groups lines whose vertical midpoints differ by at most `0.02`, sorts groups from highest Vision Y coordinate to lowest, sorts each group by ascending X, and joins text with `\n`.

Run the same `xcodebuild test` command.

Expected: helper tests pass.

- [ ] **Step 4: Implement the scanner view controller**

`PageScannerViewController` must:

- configure an `AVCaptureSession` with the back camera, `AVCaptureVideoDataOutput`, and `AVCapturePhotoOutput`;
- show `AVCaptureVideoPreviewLayer` plus one quadrilateral overlay and the approved guidance copy;
- process at most five preview frames per second on a dedicated serial queue;
- run `VNDetectRectanglesRequest` with `maximumObservations = 1`, `minimumConfidence = 0.8`, `minimumAspectRatio = 0.3`, and `minimumSize = 0.35`;
- pass the normalized corners and camera focus/exposure readiness to `RectangleStabilityTracker(requiredStableFrames: 5, tolerance: 0.02, minimumArea: 0.35)`;
- call `AVCapturePhotoOutput.capturePhoto` once when the tracker returns true;
- guard duplicate capture with `isCapturing`;
- transform rectangle coordinates from preview orientation into the captured image orientation;
- apply `CIPerspectiveCorrection` using all four detected corners;
- run `VNRecognizeTextRequest` with `.accurate`, `['en-US', 'vi-VN']`, and language correction enabled;
- return sorted non-empty text through `onComplete(.success(text))`;
- return typed failures: `camera_denied`, `camera_unavailable`, `capture_failed`, `correction_failed`, `ocr_failed`, `no_text`;
- return `cancelled` from a visible Cancel control;
- stop the capture session and release image references before dismissal.

Do not save photos to the Photos library or app documents directory.

- [ ] **Step 5: Implement the scanner bridge and register it**

`ScanAnyPageBridge` receives the Flutter view controller and binary messenger. Register channel `storybook_ar/scan_any_page`; reject concurrent calls with code `scan_in_progress`; present `PageScannerViewController`; resolve exactly one Flutter result with `{'text': text}` or `FlutterError(code: typedCode, message: nil, details: nil)`.

In `AppDelegate`, retain the bridge as a property and initialize it after `GeneratedPluginRegistrant.register` using `window?.rootViewController as? FlutterViewController`.

Update `NSCameraUsageDescription` to:

```text
The camera detects and reads a storybook page on-device and places a character in AR. Camera images are not uploaded or stored.
```

- [ ] **Step 6: Build the iOS app without running it**

```bash
flutter build ios --debug --no-codesign
```

Expected: build succeeds with both method-channel and scanner source compiled.

- [ ] **Step 7: Physical scanner checkpoint**

Pair the iPad by cable, enable Developer Mode, select the free Personal Team in Xcode, and install from Xcode. Validate English, Vietnamese with diacritics, mixed text, glare guidance, cancellation, and no duplicate capture. Do not use `flutter run` unless Phuc explicitly requests it.

Expected: one stable page transitions directly to OCR text with no shutter or save confirmation.

- [ ] **Step 8: Commit scanner implementation**

```bash
git add ios/Runner/ScanAnyPage ios/RunnerTests/ScanGeometryTests.swift ios/RunnerTests/TextObservationSorterTests.swift ios/Runner/AppDelegate.swift ios/Runner/Info.plist ios/Runner.xcodeproj/project.pbxproj
git commit -m "feat(ios): add automatic bilingual page scanner"
```

### Task 4: Flutter TTS Client and Temporary Audio

**Files:**
- Create: `lib/features/scan_any_page/tts_client.dart`
- Create: `test/tts_client_test.dart`

- [ ] **Step 1: Write failing client tests**

Use `http_mock_adapter` with the existing `ApiClient`. Tests must verify:

- text is trimmed and POSTed once to `/v1/tts`;
- request asks Dio for bytes and accepts only status 200 + `audio/mpeg` + non-empty bytes;
- bytes are written to an injected temporary directory as `scan_any_page_narration.mp3`;
- a second successful generation replaces the previous file;
- empty/whitespace and over-4,000-character text fail before HTTP;
- non-audio or empty responses throw `TtsGenerationFailure('invalid_audio')`;
- `dispose()` deletes the generated file.

Expose a `Directory Function()` injection so tests use a test-owned temporary directory and production uses `Directory.systemTemp`.

- [ ] **Step 2: Run the test red**

```bash
flutter test test/tts_client_test.dart
```

Expected: compilation fails because `TtsClient` does not exist.

- [ ] **Step 3: Implement the client**

Use this public contract:

```dart
abstract interface class TtsClient {
  Future<File> generate(String confirmedText);
  Future<void> dispose();
}

final class HttpTtsClient implements TtsClient {
  HttpTtsClient(this._apiClient, {Directory Function()? temporaryDirectory});
  // POST through ApiClient.send, validate media type and bytes, replace temp file.
}
```

Use `Options(responseType: ResponseType.bytes, headers: {'Accept': 'audio/mpeg'})`. Do not log request text or response bytes.

- [ ] **Step 4: Run tests and analyzer**

```bash
flutter test test/tts_client_test.dart
flutter analyze
```

Expected: test passes and analyzer exits successfully.

- [ ] **Step 5: Commit TTS client**

```bash
git add lib/features/scan_any_page/tts_client.dart test/tts_client_test.dart
git commit -m "feat(scan-any): download temporary narration audio"
```

### Task 5: Flutter Flow Coordinator

**Files:**
- Create: `lib/features/scan_any_page/scan_any_page_controller.dart`
- Create: `test/scan_any_page_controller_test.dart`

- [ ] **Step 1: Write state-machine tests**

Define fakes for `ScanService`, `TtsClient`, and `CharacterReader`. Cover:

- initial `idle` -> `scanning` -> `reviewingText` with OCR text;
- cancellation returns to `idle` without an error;
- scan failure exposes a scan-specific retry state;
- `confirmText` rejects empty and over-limit text;
- TTS success stores the local audio file and enters `readyForAr`;
- TTS failure retains confirmed text and can retry without rescanning;
- AR failure retains generated audio and can retry without TTS;
- reset disposes temporary audio and clears text;
- controller disposal invokes `TtsClient.dispose()`.

Use an immutable state:

```dart
enum ScanAnyPagePhase { idle, scanning, reviewingText, generatingAudio, readyForAr, openingAr, failure }

class ScanAnyPageState {
  const ScanAnyPageState({
    this.phase = ScanAnyPagePhase.idle,
    this.recognizedText = '',
    this.confirmedText = '',
    this.audioFile,
    this.failureCode,
  });
  // fields + copyWith
}
```

- [ ] **Step 2: Run the test red**

```bash
flutter test test/scan_any_page_controller_test.dart
```

Expected: compilation fails because the controller and state do not exist.

- [ ] **Step 3: Implement minimal controller**

Implement `ScanAnyPageController` as a Riverpod `Notifier<ScanAnyPageState>` with injected dependencies in its constructor. Public methods:

```dart
Future<void> startScan()
Future<void> confirmText(String text)
Future<void> retryTts()
Future<void> openCharacterReader()
Future<void> reset()
```

Use generation counters or identity checks so late async results cannot overwrite state after reset/disposal. `openCharacterReader()` requires an existing file and never regenerates audio.

- [ ] **Step 4: Run coordinator tests**

```bash
flutter test test/scan_any_page_controller_test.dart
```

Expected: all state and retention tests pass.

- [ ] **Step 5: Commit coordinator**

```bash
git add lib/features/scan_any_page/scan_any_page_controller.dart test/scan_any_page_controller_test.dart
git commit -m "feat(scan-any): orchestrate OCR TTS and AR flow"
```

### Task 6: Flutter Screen, Providers, Route, and Entry

**Files:**
- Create: `lib/features/scan_any_page/scan_any_page_screen.dart`
- Modify: `lib/core/di.dart:1-76`
- Modify: `lib/core/router/app_router.dart:5-98`
- Modify: `lib/features/library/library_screen.dart:26-77`

- [ ] **Step 1: Add providers**

In `di.dart`, add providers for `ScanService`, `CharacterReader`, and `TtsClient`. Add a family/notifier provider for a fresh flow controller per screen lifecycle. Production implementations are `NativeScanService`, `NativeCharacterReader`, and `HttpTtsClient(ref.watch(apiClientProvider))`.

- [ ] **Step 2: Build the approved screen states**

Implement the storyboard states from `scan-any-page-wireframes.html`:

- entry with `Scan a page`;
- native scanner launch and progress;
- editable multiline OCR review with `Use this text` and `Scan again`;
- character-count display and disabled confirmation over 4,000 characters;
- TTS loading with same-Wi-Fi explanation;
- TTS retry retaining editable text;
- `Place character` action after audio exists;
- AR retry without rescanning/regenerating;
- reset to scan another page.

Do not add a language selector. Label OCR as `English + Vietnamese`. Do not claim content is reviewed. Do not display or retain the captured image.

- [ ] **Step 3: Add independent route and library entry**

Add:

```dart
static const scanAnyPage = '/scan-any-page';
```

and a `GoRoute` building `ScanAnyPageScreen`. Add one prominent action above the library grid, not inside each story card:

```dart
FilledButton.icon(
  onPressed: () => context.push(AppRoutes.scanAnyPage),
  icon: const Icon(Icons.document_scanner_rounded),
  label: const Text('Scan any page'),
)
```

Leave `AppRoutes.scan(storyId)`, `ScanStoryScreen`, and the existing `Scan the book` story action unchanged.

- [ ] **Step 4: Run focused and regression checks**

```bash
flutter test test/native_scan_service_test.dart test/native_character_reader_test.dart test/tts_client_test.dart test/scan_any_page_controller_test.dart
flutter analyze
```

Expected: all focused tests pass and analyzer exits successfully.

- [ ] **Step 5: Commit Flutter integration**

```bash
git add lib/core/di.dart lib/core/router/app_router.dart lib/features/library/library_screen.dart lib/features/scan_any_page/scan_any_page_screen.dart
git commit -m "feat(scan-any): add arbitrary page reading flow"
```

### Task 7: Prototype Character Asset Gate

**Files:**
- Add: `ios/Runner/CharacterReader/toy_drummer.usdz`
- Create: `ios/Runner/CharacterReader/ASSET_LICENSE.md`
- Modify: `ios/Runner.xcodeproj/project.pbxproj`

- [ ] **Step 1: Retrieve the Apple prototype asset**

Download Apple's `toy_drummer.usdz` from `https://developer.apple.com/quick-look-gallery/models/drummertoy/toy_drummer.usdz` into `ios/Runner/CharacterReader/toy_drummer.usdz`. Do not substitute a third-party model under the same filename.

- [ ] **Step 2: Record provenance before use**

Create `ASSET_LICENSE.md` with:

```markdown
# toy_drummer.usdz

- Source: Apple AR Quick Look Gallery
- Source URL: https://developer.apple.com/quick-look-gallery/models/drummertoy/toy_drummer.usdz
- Retrieved: 2026-08-14
- Intended use: local physical-device prototype only
- Distribution status: not approved for TestFlight, App Store, public download, or redistribution until the applicable Apple terms are reviewed
- Required action before external distribution: replace this file or document explicit redistribution permission
```

Apple's gallery provides the download but no model-specific redistribution grant. Its site terms restrict copying and distribution without Apple's prior written consent, so this binary remains local-prototype-only.

- [ ] **Step 3: Add the USDZ to the Runner resources phase**

Add the asset file reference to the Runner group and `PBXResourcesBuildPhase`. Build:

```bash
flutter build ios --debug --no-codesign
```

Expected: build succeeds and `Runner.app/toy_drummer.usdz` exists in the build output.

- [ ] **Step 4: Stop if provenance cannot be established**

If the exact Apple source and prototype terms cannot be documented, do not add or commit the binary. Report the asset blocker and request a replacement choice. This is a deliberate delivery gate, not permission to download a different model silently.

- [ ] **Step 5: Commit the documented prototype asset**

```bash
git add ios/Runner/CharacterReader/toy_drummer.usdz ios/Runner/CharacterReader/ASSET_LICENSE.md ios/Runner.xcodeproj/project.pbxproj
git commit -m "chore(ar): add documented prototype character asset"
```

### Task 8: Native RealityKit Character Reader

**Files:**
- Create: `ios/Runner/CharacterReader/CharacterReaderViewController.swift`
- Create: `ios/Runner/CharacterReader/CharacterReaderBridge.swift`
- Modify: `ios/Runner/AppDelegate.swift`
- Modify: `ios/Runner.xcodeproj/project.pbxproj`

- [ ] **Step 1: Implement the native AR view**

`CharacterReaderViewController(audioURL:onComplete:)` must:

- verify `ARWorldTrackingConfiguration.isSupported` and the local MP3 exists;
- run `ARWorldTrackingConfiguration` with `.horizontal` plane detection and environment texturing;
- show movement guidance until a center-screen raycast hits an estimated or existing horizontal plane;
- show a reticle at the current raycast result;
- place exactly one `AnchorEntity(world:)` and cloned model on tap;
- load `toy_drummer.usdz` from the main bundle;
- scale the model to a visible table-sized bounding box and preserve its aspect ratio;
- play the model's first available animation repeatedly, or apply a gentle native bob if no animation exists;
- reveal `Read` only after placement;
- use `AVAudioPlayer` for the local MP3 with play/pause controls;
- animate a sound-wave badge only while `audioPlayer.isPlaying`;
- keep the anchor stable as the camera moves;
- return `completed` when the user closes after placement/playback and `cancelled` when closing before playback;
- pause audio and AR session in dismissal/deinit;
- emit typed failures `ar_unsupported`, `audio_missing`, `model_missing`, `model_load_failed`, `audio_failed`.

- [ ] **Step 2: Implement and register the AR bridge**

Register `storybook_ar/character_reader`. `openCharacterReader` requires `audioFilePath`, rejects concurrent presentation with `reader_in_progress`, validates the path, presents the view full screen, and resolves exactly once.

Retain `CharacterReaderBridge` in `AppDelegate` alongside `ScanAnyPageBridge`.

- [ ] **Step 3: Build iOS and run native unit tests**

```bash
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'
flutter build ios --debug --no-codesign
```

Expected: XCTest and no-codesign build pass. AR behavior remains a device-only checkpoint.

- [ ] **Step 4: Physical AR checkpoint**

Install from Xcode using Personal Team signing. Validate table detection, reticle movement, one placement, stable anchoring, idle animation/fallback, Read gating, play/pause, speaking-indicator synchronization, cancellation, and resuming after background/foreground.

Expected: the character remains attached to the table while moving the iPad and speaks only after explicit Read.

- [ ] **Step 5: Commit AR bridge**

```bash
git add ios/Runner/CharacterReader/CharacterReaderViewController.swift ios/Runner/CharacterReader/CharacterReaderBridge.swift ios/Runner/AppDelegate.swift ios/Runner.xcodeproj/project.pbxproj
git commit -m "feat(ios): add table-anchored character reader"
```

### Task 9: End-to-End Local Demo Verification

**Files:**
- Modify only if failures require directly related fixes from Tasks 1-8.

- [ ] **Step 1: Configure the secret locally**

Put the supplied key in untracked `backend/.env` using a local editor. The resulting file must define these four names, with the actual secret as the value of `OPENAI_API_KEY`:

```dotenv
OPENAI_API_KEY=
OPENAI_TTS_MODEL=gpt-4o-mini-tts
OPENAI_TTS_VOICE=coral
OPENAI_TTS_TIMEOUT_SECONDS=30
```

The empty value above documents the file shape; do not start the backend until the local `.env` contains the actual supplied key. Never paste the key into source, tests, shell history, logs, or this plan.

- [ ] **Step 2: Start the backend on the LAN**

From `backend/`, run:

```bash
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

From another terminal, derive the Mac's Wi-Fi LAN IP and verify it:

```bash
MAC_LAN_IP="$(ipconfig getifaddr en0)"
test -n "$MAC_LAN_IP"
curl "http://$MAC_LAN_IP:8000/health"
```

Expected: `{"status":"ok"}`. This is a local, reversible development server action; it is not a deployment.

- [ ] **Step 3: Build with the LAN API URL**

In the same terminal where `MAC_LAN_IP` is defined, build with:

```bash
flutter build ios --debug --no-codesign --dart-define="API_BASE_URL=http://$MAC_LAN_IP:8000"
```

Expected: build succeeds. If the active network interface is not `en0`, obtain its address with `ipconfig getifaddr <interface>` and assign that value to `MAC_LAN_IP`. Do not hard-code the LAN IP in tracked files.

- [ ] **Step 4: Install through Xcode and execute the acceptance matrix**

Do not invoke `flutter run`. Install/run from Xcode only after selecting Phuc's Personal Team and connected iPad.

Validate:

1. English large-text page auto-captures and OCR is editable.
2. Vietnamese diacritics survive OCR or are correctable.
3. Mixed English/Vietnamese text is sent in one request and produces one clip.
4. No backend request occurs before `Use this text`.
5. Backend-unreachable retry retains text.
6. TTS failure does not silently use on-device TTS.
7. AR failure/retry does not regenerate speech.
8. Table placement, stable anchor, explicit Read, pause/resume, idle motion, and speaking indicator work.
9. Reset deletes temporary audio and returns to entry.
10. Existing `Scan the book` preview route still opens unchanged.

- [ ] **Step 5: Run final automated checks**

```bash
flutter analyze
flutter test test/native_scan_service_test.dart test/native_character_reader_test.dart test/tts_client_test.dart test/scan_any_page_controller_test.dart
uv run --directory backend pytest -v
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'
git diff --check
```

Expected: every command exits successfully.

- [ ] **Step 6: Document observed demo limitations**

Add a short `Physical device results` section to the design spec only if measured behavior differs materially from its assumptions. Record device/iPadOS, representative page conditions, OCR corrections needed, chosen voice quality for mixed text, time-to-audio, and AR placement behavior. Do not add speculative roadmap content.

- [ ] **Step 7: Commit final directly related fixes or results**

Stage only files changed for this feature, inspect `git diff --staged`, then commit:

```bash
git commit -m "test(scan-any): validate physical device demo"
```

Skip this commit if no tracked files changed during verification.

---

## Execution Rules

- Do not use `flutter run`; install through Xcode for physical-device checkpoints unless Phuc explicitly requests otherwise.
- Do not run widget, integration, or end-to-end automated suites.
- Do not deploy or push. Local LAN backend execution is the only network environment in scope.
- Do not expose the OpenAI key to Flutter, logs, tests, commits, or chat.
- Do not upload camera frames. The native scan bridge returns text only.
- Do not modify the known-story `PageDetector`, manifest, scan session, or AR scene flow.
- Stop at the asset gate if Apple sample provenance cannot be documented.
- Before each commit, inspect status/diff and stage only feature files; commits require Phuc's explicit execution approval.
