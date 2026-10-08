# ElevenLabs-only scanned-page narration

## Decision and scope
- User chose fixed-page narration, ElevenLabs, and option 1 (`eleven_v3`).
- User supplied voice ID `5yEPTrA0uAhZsBEhHjfi`.
- User explicitly chose ElevenLabs as the only scanned-page TTS provider.
- User confirmed the code changes in this session.
- The API key remains an environment setting and must not be put in source or chat.
- The shared `/v1/tts` endpoint still uses the OpenAI service.
- Authored-story default voice metadata still uses OpenAI configuration.
- No deployment, schema migration, API request, or key use is authorized here.

## Read evidence
- `backend/app/routers/speakable_page.py:52-97` verifies approved OCR lines,
  normalizes speech text, emits ordered MP3 entries in a ZIP, caps entries
  at 2 MiB and the bundle at 32 MiB, and maps all failures to a 502.
- `backend/app/routers/tts.py:13-50` independently uses OpenAiTtsService.
- `backend/app/repositories/stories.py:96-109` also reads the OpenAI voice.
- `backend/app/services/tts.py:1-53` is therefore shared and stays in place.
- `backend/app/config.py:4-23` loads environment variables with BaseSettings.
- `backend/.env.example:1-15` documents nonsecret settings and blank API keys.
- `backend/tests/test_page_audio.py:125-245` pins clip order and no partial ZIP.
- `backend/tests/test_tts_diagnostics.py:1-92` pins the existing OpenAI path.
- `backend/tests/test_tts.py:1-162` pins the independent `/v1/tts` route.
- `backend/tests/conftest.py:24-30` drops and recreates a test DB schema;
  do not invoke those fixtures without explicit migration/schema confirmation.
- `lib/features/scan_any_page/page_validation_client.dart:68-126` expects
  numbered MP3 entries and a ZIP Content-Type.
- `lib/features/scan_any_page/scanned_page_ar_audio.dart:37-66` passes ordered
  MP3 clips to native AR.
- ElevenLabs API docs: https://elevenlabs.io/docs/api-reference/text-to-speech/convert
- ElevenLabs models: https://elevenlabs.io/docs/overview/models#eleven-v3
- Documentation confirms POST `/v1/text-to-speech/{voice_id}`, header
  `xi-api-key`, JSON `text`/`model_id`, and MP3 output.
- Documentation lists Vietnamese support for `eleven_v3`.
- Actual voice quality, key permissions, billing, and voice availability
  are not verified without a live request.

## File map
- `backend/app/services/elevenlabs_tts.py` (new)
  - Own one authenticated HTTPS text-to-speech request per text segment.
  - Use stdlib urllib and no dependency changes.
  - Fix the API host and output format; never accept a URL from a response.
  - Return bounded MP3 bytes to the scanned-page router.
  - Bound timeout, input length, response length, and configuration values.
  - Report sanitized errors; do not log keys, OCR, audio, or response bodies.
- `backend/app/config.py` (update)
  - Add blank ElevenLabs API key and configured voice/model/timeout fields.
  - Keep the OpenAI settings for `/v1/tts` and authored-story metadata.
- `backend/.env.example` (update)
  - Document the blank secret, selected voice ID, and model.
  - Clarify which backend endpoint each provider setting affects.
- `backend/app/routers/speakable_page.py` (update)
  - Construct ElevenLabs service after auth, profile, proof verification.
  - Keep normalized line order and the ZIP contract exactly.
  - Keep existing error mapping and no partial response.
  - Update only the stale OpenAI-specific scanned-page comment.
- `backend/tests/test_elevenlabs_tts.py` (new)
  - Mock the HTTP boundary with no live ElevenLabs request.
  - Assert URL, voice ID, headers, model, text, MP3 format, timeout.
  - Check missing key, timeout/HTTP errors, empty/oversized payload.
  - Check no secret/OCR text enters logs or public error strings.
- `backend/tests/test_page_audio.py` (update)
  - Patch ElevenLabs service provider in existing bundle tests.
  - Keep proof and clip-order assertions.
  - Assert one failed clip returns no partial bundle.
- `docs/plans/2026-10-08-elevenlabs-scanned-page-tts.md` (new)
  - Record interfaces, tests, spec coverage, and verification gaps.

## Task boundaries
- `OpenAiTtsService` stays live for `/v1/tts`; no fallback is wired into
  `/v1/speakable-page/audio`.
- No change to frontend, AR, authored-story voice selection, OCR, or consent.
- ElevenLabs config must not contain an API key default or test credential.
- Treat voice ID as public configuration, API key as secret configuration.
- The selected voice ID is configurable but defaults to the user's ID.
- Model defaults to `eleven_v3` as explicitly chosen.
- Do not guess at a new speech speed or override ElevenLabs voice settings.
- Keep each approved OCR line paired with one numbered MP3 clip.
- Keep the existing Vietnamese number normalization before synthesis.
- Do not pass a line index, altered text, or other metadata into TTS.
- Do not retry POST requests automatically; a retry may charge twice.
- Do not return external error details or partially generated clips to clients.
- Use bounded read of 2 MiB + 1 byte before ZIP assembly.
- Validate the MP3 framing bytes or a recognized ID3 header.
- Prefer a local unit test over calling an external service.

## Exact interfaces
- `ElevenLabsTtsService.generate(text: str) -> bytes` provides one MP3 clip.
- `get_elevenlabs_tts_service()` caches the service, matching existing style.
- Use existing `TtsUpstreamError` type for the router's generic error mapping.
- `Settings.elevenlabs_api_key` reads `ELEVENLABS_API_KEY`.
- `Settings.elevenlabs_voice_id` reads `ELEVENLABS_VOICE_ID`.
- `Settings.elevenlabs_model_id` reads `ELEVENLABS_MODEL_ID`.
- `Settings.elevenlabs_tts_timeout_seconds` reads `ELEVENLABS_TTS_TIMEOUT_SECONDS`.
- POST `https://api.elevenlabs.io/v1/text-to-speech/{voice_id}`.
- Query `output_format=mp3_44100_128`.
- Header `xi-api-key` is backend-only.
- JSON body contains `text` and `model_id`.
- Return ZIP names `000.mp3`, `001.mp3`, etc unchanged.
- Return Content-Type `application/zip`, no-store unchanged.
- Do not add a new Flutter/network payload field.

## Task order
1. Inspect all service callers before changing provider selection.
2. Save this plan before implementation.
3. Add config and the ElevenLabs HTTP adapter.
4. Change only the scanned-page router provider.
5. Adjust its existing mocked page-audio tests.
6. Add provider unit tests using mocked HTTP responses.
7. Run safe unit checks without test DB schema fixtures.
8. Inspect all changed files and `git diff --check`.
9. Report configuration and unverified real-audio behavior.

## Review focus
- Keep a wrong or missing API key from starting a real request.
- Do not accidentally route `/v1/tts` to ElevenLabs.
- Do not overwrite the user's unrelated Android/Flutter/native changes.
- Ensure the selected voice ID is sent as a path segment, not a secret.
- Reject invalid voice IDs before constructing a URL.
- Ensure HTTP errors do not leak OCR or key in logs/response.
- Reject HTML/JSON responses masquerading as MP3.
- Bound both network time and response size.
- A failed later segment must not return earlier clips.
- MP3 files must keep original line order after normalization.
- The client must still accept and copy every clip into AR.
- The default voice's Vietnamese sound is unknown without a real sample.
- Account entitlement for this specific voice and v3 model is unknown.
- Sequential per-line synthesis can take time on long scans.

## Checks and spec coverage
- Run `python3 -m unittest` for the new isolated HTTP adapter tests.
- Do not invoke backend pytest fixtures that drop/recreate schemas without
  explicit user confirmation in the current message.
- Compile changed Python files without calling ElevenLabs.
- Run `git diff --check` and review intended modified/untracked files.
- The full integration requires a configured key and real backend environment.
- Fixed-page narration only: ElevenLabs service used by speakable_page.
- Only provider for this route: no OpenAI fallback branch.
- Voice/model: configurable chosen ID and `eleven_v3`.
- Narration: one verified MP3 per original OCR line, bundled unchanged.
- Secret handling: environment only, no key in source, tests, or logs.

## Verification results
- VERIFIED: eight isolated ElevenLabs adapter tests passed with mocked HTTP.
- Command from backend: `python3 -m unittest discover -s tests -p test_elevenlabs_tts.py -v`.
- VERIFIED: four existing OpenAI speech diagnostics tests passed unchanged.
- Command: `python3 -m unittest discover -s tests -p test_tts_diagnostics.py -v`.
- VERIFIED: three existing Vietnamese page-narration tests passed.
- Command: `python3 -m unittest discover -s tests -p test_page_narration.py -v`.
- VERIFIED: Python syntax compilation passed for the config, new service,
  scanned-page router, and page-audio integration test source.
- VERIFIED: `git diff --check` passed after changes.
- VERIFIED: only the scanned-page route imports the ElevenLabs getter;
  the independent `/v1/tts` route still imports the OpenAI getter.
- VERIFIED: the new service refuses redirects, so an upstream redirect
  cannot forward the `xi-api-key` header to a different host.
- VERIFIED: response byte count is bounded before ZIP assembly, and fake
  HTTP errors/invalid media are mapped to generic TtsUpstreamError.
- NOT RUN: backend pytest `test_page_audio.py` and `test_tts.py` because
  the shared session fixture drops and recreates database schema.
- NOT RUN: any request to ElevenLabs, any real voice sample, or deployment.
- UNKNOWN: user's key validity, voice access, model entitlement, accent,
  real-page latency, and how `eleven_v3` sounds in Vietnamese.
- The `speech.mp3` untracked file and all unrelated work were preserved.
- Reviewer escalation skipped because `hawkeye` is not exposed in this session.

## Follow-up needed
- User sets `ELEVENLABS_API_KEY` in the backend environment; do not put it
  in the mobile app or paste it in chat.
- Restart the backend under its normal deployment workflow only after
  explicit approval in the current session.
- Test one short Vietnamese page with `13`, one English page, and a later
  failure to confirm pronunciation, latency, and complete ZIP delivery.
- Run database-backed HTTP tests only in a disposable test database after
  explicit approval for the schema-changing test fixture.
