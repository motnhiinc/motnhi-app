# storybook_ar — Interactive Storybook Voice + AR (Flutter client)

The **Phase-1 MVP-lite mobile client** for the Interactive Storybook Voice + AR
platform. It turns curated children's stories into narrated, interactive, AR
reading experiences for ages 3–8, with parents in control.

This is **one slice** of the larger platform described in
`interactive_storybook_voice_ar_product_technical_spec.md` and
`SYSTEM_ARCHITECTURE.md`. The backend API, async content-production workers, and
content studio are separate, later slices. Design notes for this slice:
`docs/superpowers/specs/2026-06-14-flutter-mvp-client-design.md`.

## What's implemented

- **Parent onboarding** with explicit consent and a data-minimized child profile
  (nickname optional, age band not birthday, mic off by default). (§7.2.1, §14)
- **Parental gate** (math challenge) guarding the parent dashboard + settings. (§7.2.3)
- **Story library** — browse 5 demo stories, filter by theme, age-band aware. (§7.1.1)
- **Story player** — paged reading, per-segment narration, live sentence
  highlighting, tap-a-sentence to jump, replay, page navigation. (§7.1.2)
- **Audio engine** — plays bundled per-segment clips when present, else falls back
  to on-device TTS (clearly flagged DEV-ONLY). Per-speaker pitch differentiation. (§9.4.3)
- **AR story mode** — live camera preview with the page's `scene_json` character
  overlaid; tap the character to hear its line. (§7.1.4, §9.3)
- **Interactive questions** — 3 per story, image/emoji multiple choice, recorded
  as analytics events. (§7.1.5)
- **Bedtime mode** — calmer pacing + dark, dimmer theme, no autoplay onward. (§7.1.6)
- **Parent dashboard** — stories completed, reading time, question accuracy,
  recently read, simple recommendations. (§7.2.2)
- **Reading settings** — voice speed, SFX/music volume, language, bedtime default,
  AR + microphone permissions. (§7.2.4)

All child-facing content is consumed as pre-authored, local assets — the app
never generates story content live for a child (§13.2).

## Architecture

`Riverpod 3` (state) · `go_router 17` (routing + gate guards) · `freezed 3`
(models mirroring the spec §10 schema / §11 API DTOs) · `just_audio` + `flutter_tts`
(audio) · `arkit_plugin` / `arcore_flutter_plugin` / `camera` (AR).

```
lib/
  core/        di, router (+ gate guards), theme (day + bedtime)
  data/        models (freezed), sources (bundled JSON + prefs), repositories
  features/    onboarding, parental_gate, library, player, questions, ar,
               dashboard, settings, profile
  shared/      reusable child-safe widgets
assets/data/   manifest.json + 5 story detail files (shaped like GET /v1/stories/{id})
```

The data layer is abstracted behind repository interfaces with **local
implementations**; swapping to the real backend is a repository + provider-override
change, no UI rework.

## Run

```bash
flutter pub get
dart run build_runner build      # regenerate models after editing them
flutter run                      # iOS / Android device recommended for camera/AR
```

## Verify

```bash
flutter analyze                  # clean: no issues
flutter test test/content_parsing_test.dart test/widget_test.dart
```

## Known follow-ups (deferred, by design)

- **Real ARKit/ARCore image-target tracking** is gated behind
  `ArCapabilities.nativeImageTrackingWired` (currently `false`) and runs in
  camera-preview mode until wired + validated **on a physical device with printed
  reference images**. The full `scene_json → asset → tap-audio` data path already runs.
- **Real narration audio** — the engine consumes bundled per-segment clips, but
  none exist yet (the content/TTS pipeline is a separate slice), so it currently
  falls back to on-device TTS.
- **Cover art, page illustrations, character rigs** — placeholders until real
  assets land; JSON already points at the intended `assets/images/...` paths.
- **Backend, workers, content studio, signed-URL CDN delivery, activation codes,
  classroom mode, localization** — separate platform slices.
