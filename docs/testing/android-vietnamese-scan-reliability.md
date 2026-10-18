# Android Vietnamese scan verification

## Google Cloud Vision OCR (2026-10-18)

Updated scan clients capture the JPEG without native OCR, then send
`ocr_provider: "google_vision"` to `/v1/speakable-page/validate`.
The backend uses `DOCUMENT_TEXT_DETECTION`; text, reading order, language and
highlight boxes come from Vision. There is no LLM correction or rewriting pass.
OpenAI still validates page suitability/text matching and generates speech.
Approval binds the Vision text and detected segment languages; clients reject
approvals without `recognized_lines` rather than falling back to native OCR.

To try it:
1. Enable billing and **Cloud Vision API** in a Google Cloud project.
2. Create an API key restricted to Cloud Vision API (and server IP if practical).
3. Set `GOOGLE_VISION_API_KEY` in `backend/.env` locally or
   `backend/deploy/.env` for Compose. Never put this key in Flutter.
4. Deploy/restart the backend, then rebuild the app (native capture code changed).
   Keep `OPENAI_API_KEY` with speech and chat/completions access.

`GOOGLE_VISION_TIMEOUT_SECONDS` defaults to 15. Native OCR remains available to
other features and legacy validation requests. Deploy backend and client together;
the removed `correct_ocr` protocol is no longer supported.
Compare Vietnamese diacritics, names, mixed-language text, reading order and
capture-to-ready time on real pages. Tests mock providers; they do not establish
live OCR accuracy. Audio still waits for the complete ZIP.

### Temporary OCR diagnostics

OCR text logging is enabled by default. An explicit
`SCAN_OCR_DEBUG_LOGGING=false` disables it. Recreate the API container after
deploying the updated code or changing this setting. Follow logs with
`docker compose -f docker-compose.prod.yml logs -f api` from `backend/deploy`.
`scan_ocr_raw` shows Vision's text (up to 16,000 characters) and page dimensions
before geometry parsing; `scan_ocr_lines` shows the parsed text/language/boxes
before OpenAI validation. `scan_failure` identifies the failing stage and
exception type without logging exception messages, images or credentials.
These text logs may contain private book/page content, including blocked pages.
Disable the flag and recreate the container after debugging; existing log
records remain subject to your deployment's log retention policy.

## Implementation and rollout

Deploy additive backend support before the client. The active route now uses
`ScanPageCoordinator`; the old controller is unchanged. Language defaults to `vi`
on Android and `en` elsewhere, and an explicit selection is stored independently
of UI/device locale. Changing language starts a new capture and approval session.
Legacy requests without a language retain exact-text, unbound proof behavior.

Configuration (environment variable names are uppercase):

| Setting | Initial value |
| --- | --- |
| `PAGE_AUDIO_CONCURRENCY` | 3 |
| `PAGE_AUDIO_PROCESS_CONCURRENCY` | 6 |
| `PAGE_AUDIO_QUEUE_SECONDS` | 5 |
| `PAGE_AUDIO_DEADLINE_SECONDS` | 30 |
| `PAGE_AUDIO_TRANSIENT_RETRIES` | 1 |
| `OPENAI_PAGE_VALIDATION_TIMEOUT_SECONDS` | 15 |
| `PAGE_LANGUAGE_INSTRUCTIONS_ENABLED` | true |
| `OPENAI_TTS_MODEL` / `OPENAI_TTS_VOICE` | gpt-4o-mini-tts / coral |

Run `uv run python verify_scan_configuration.py` in `backend` before deployment.
Optionally add `--provider-smoke-test` to verify live instruction support (incurs
two speech requests; it does not save clips). Disabling instructions fails explicit
language requests visibly; it never silently ignores their intent. Concurrency 1
provides the serial comparison. Process capacity is **not** a deployment-global
rate limiter: choose worker/replica counts with the provider's actual budget.
Per-page parallelism is capped at 8, regardless of a page's line count.

Quality version 1 is **observational only**. There is deliberately no switch to
enable uncalibrated retakes. ML Kit confidence/language are optional; unknown
metadata must remain unknown. Reading-order tolerance has not been retuned.

## Diagnostics

`ScanStages` records random attempt IDs; HTTP requests also carry new operation IDs
for each stage/retry. Backend logs validate these headers as UUIDs before logging.
No profile identifier, OCR text, image/audio bytes, token or provider body belongs
in diagnostic logs. These are bounded local console events, not a new remote
telemetry service. Capture tagged `ScanStages` events with `adb logcat` for internal
profile/release runs. Server stage events inherit Uvicorn's INFO logging sink;
retain them explicitly in deployment log collection.

Native stages separate scanner intent acquisition, the managed scanner round trip
(which includes human positioning/review), decode, EXIF transform preparation,
resize/rotation transform, JPEG encoding and OCR. Rotation and resize use one
bitmap transform to bound allocation. The coordinator adds native processing time
to capture-return-to-ready, so this metric does not exclude local OCR.

Validation/audio round-trip timings, backend provider/queue/clip/bundle timings,
extraction and player loading are separate. `listen_to_first_playback_progress`
comes from advancing player position, **not** `play()` completion. It is a playback
instrumentation proxy, not acoustic proof that a muted device emitted sound;
measure actual first sound on the physical devices before claiming the 500-ms goal.

`cold_run` means first scanner invocation in this bridge's lifetime, not proof of
a fresh GMS install. Record first-install scanner availability separately. Network
category is measured at scan start; annotate network changes during a run.

## Corpus and device protocol (pending)

Generate reproducible **synthetic** fixtures with:

```sh
cd backend
uv run python ../tools/generate_scan_corpus.py --output /approved/local/corpus
```

The manifest contains 50 original transcribed Vietnamese pages and English/mixed
regressions, line order, conditions and a held-out split. These are controlled
fixtures, **not** a substitute for 50 authorized physical book-page captures.
Synthetic glare is only a proxy. Add glossy paper, curved bindings, actual rotated
captures and illustrated/multi-column book layouts, with human readability labels.
Do not infer readability or calibrate a gate from OCR confidence. Keep private
captures and transcripts outside Git and outside normal diagnostic logs.

Confirm the co-founder's actual Android model and a lower/mid-range GMS device;
no Android device was connected during implementation. Use baseline/candidate
release or profile builds with identical pages, devices and network conditions.
Record cold/warm runs, Wi-Fi/mobile, repeated scans, cancellation, background/resume
and network loss. Measure peak heap on the low-memory device. Intermediate ARGB
storage is capped at 128 MiB; unsupported/oversized/OOM decode paths fail safely.

For every attempt record build/device/network, condition, page length, outcome,
reason, retry count, stage durations and quality version/signals. Include failed
attempts in completion-rate denominators. Compute NFC character error rate and
diacritic errors on the held-out set; evaluate reading order separately. Run native
Vietnamese listening panels on both ground-truth and OCR-derived text, keeping
voice `coral` fixed for the first comparison. Never report configuration changes
as evidence of improved pronunciation.

## Automated and manual acceptance

- Android: `:app:testDebugUnitTest` (Robolectric native bitmap/EXIF fixtures,
  resizing/no-upscale/JPEG bounds, invalid decode, Unicode/overflow and existing
  reading-order tests).
- Flutter: `flutter analyze` and `flutter test`; coordinator tests cover retained
  stage retries, NFC/language, expiry/invalid proof, blocked state, incomplete media,
  cancellation/stale file cleanup and immediate player-event transitions.
- Backend: `uv run pytest tests/test_page_validation.py tests/test_page_audio.py
  tests/test_scan_reliability.py tests/test_tts.py` against a disposable PostgreSQL
  test database. Do not point its destructive schema fixture at production data.
- Before releasing: use Marionette on a running debug/profile Android app for
  happy path, retries without extra scanner launches, disposal/new-scan stress,
  pause/resume/replay and accessibility. Physical camera/voice acceptance remains
  separate from simulated services and widget/unit tests.

Implementation verification on 2026-10-14 (Flutter 3.38.10): `flutter analyze`
reported no issues; Flutter's full suite and a native-channel → validation → ZIP
integration check passed; 184 backend tests and 65 Android unit tests passed.
The synthetic generator and deployment configuration check also ran successfully.
No Android device/Android VM service was connected, so Marionette device checks,
live-provider instruction smoke tests and physical/listening acceptance were not run.

Release status: automated implementation is testable; physical baseline, >=95%
completion, <=1% held-out CER, false-retake calibration, >=30% p95 improvement,
first audible sound and native-speaker >=4/5 ratings are **not yet measured**.
Cloud OCR, progressive playback, custom camera and voice/provider changes remain
out of scope. Do not enable quality enforcement or expand rollout on unit tests alone.
