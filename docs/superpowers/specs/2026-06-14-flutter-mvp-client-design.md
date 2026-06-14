# Flutter MVP-lite Client — Design

> First implementation slice of the Interactive Storybook Voice + AR platform.
> Source of truth: `interactive_storybook_voice_ar_product_technical_spec.md` (spec) and `SYSTEM_ARCHITECTURE.md` (architecture). Section refs like (§9.2) point at the spec.

## Scope of this slice

The platform decomposes into four independently-buildable subsystems (mobile client, backend API, async workers, content studio). **This slice is the mobile client only** — Phase-1 "MVP-lite":

- Parent onboarding (create child profile, set permissions) (§7.2.1)
- Parental gate guarding parent-only routes (§7.2.3)
- Story library: browse 3–5 stories, filter by age band / theme, unlocked + downloaded state (§7.1.1)
- Story player: paged reading, gapless per-segment narration, current-sentence highlighting, replay, read-to-me (§7.1.2)
- Character voices via per-segment `voice_id` metadata (§7.1.3)
- Interactive questions: 3 per story, image multiple-choice / tap-the-object (§7.1.5)
- Bedtime mode: slower narration, dimmer UI, lower SFX, no autoplay (§7.1.6)
- AR story mode: on-device image-target AR, 1 hero scene per story, tap-character→play-audio (§7.1.4, §9.3)
- Parent dashboard: stories completed, reading time, question accuracy, recommendations (§7.2.2)
- Reading settings (§7.2.4)

Backend, workers, and content studio are **out of scope** here. The client runs on **local bundled content** shaped exactly like the §11 API responses, so swapping to a real API later is a repository-implementation change only.

## Decisions (locked with the user)

| Decision | Choice | Rationale |
|---|---|---|
| Slice width | Phase-1 MVP-lite client | Broader than the bare magic-moment; full child + parent surface |
| AR | Real on-device (ARKit + ARCore) behind an abstraction, camera-preview fallback | User chose real AR; abstraction keeps the app runnable without targets |
| Audio source | Playback engine on bundled per-segment audio assets + `flutter_tts` DEV-ONLY fallback | Mirrors the real pre-generated contract; runs today before real clips exist |
| State / routing / models | Riverpod 3.x + go_router 17.x + freezed 3.x | Modern, testable, clean API swap later |

## Architecture

Layered, feature-first:

```
lib/
  main.dart                  # ProviderScope + bootstrap
  app.dart                   # MaterialApp.router, themes
  core/
    theme/                   # warm "day" theme + calm "bedtime" theme
    router/                  # go_router config + parental-gate redirect guard
    constants/               # app-wide constants, asset paths
  data/
    models/                  # freezed models mirroring spec §10 schema + §11 API DTOs
    sources/                 # LocalContentSource (bundled JSON), KeyValueStore (prefs)
    repositories/            # abstract repos + local impls
  features/
    onboarding/  parental_gate/  library/  player/  questions/  ar/  dashboard/  settings/
  shared/widgets/            # reusable child-safe widgets (BigButton, etc.)
assets/
  data/stories.json          # library + per-story detail, §11-shaped
  data/<story>/...           # page images, audio segments, ar scene json
```

### Data model (freezed, mirrors §10 exactly)

`Story`, `StoryPage`, `NarrationSegment`, `ArScene` (+ `ArAsset`, `ArInteraction`), `ChildProfile`,
`StorySession`, `InteractionEvent`, `Question` (+ `AnswerChoice`). Enums for `age_band`,
`content_status`, session `mode`, `ar` anchor/asset/action types. Field names and constraints
follow the spec's SQL/JSON verbatim (e.g. `age_band ∈ {3-4,5-6,7-8}`, `speed NUMERIC(4,2)`,
segment `start_ms`/`end_ms`). Questions are not a spec DB table but are required by §7.1.5; modeled
as a client-side type carried in story content.

### Repositories (abstract → local impl)

- `StoryRepository` — `getLibrary({ageBand, language})` → §11.1; `getStory(id)` → §11.2 (pages,
  segments, ar scenes, questions, asset manifest). Local impl reads `assets/data/stories.json`.
- `ProfileRepository` — CRUD child profile + parent settings; persisted via `shared_preferences`.
- `SessionRepository` — start session (§11.3), record events (§11.4), resume state; persisted locally.
- `EntitlementRepository` — `is_unlocked` per story; local impl unlocks all demo content.

Each returns plain models; Riverpod `AsyncNotifier`s expose them to the UI. Swapping local→HTTP is a
new repo impl + provider override, no UI change.

### Audio Playback Engine (§9.4.3)

`just_audio` + `audio_session`. Builds a gapless playlist from `narration_segments` ordered by
`sort_order`, using `start_ms`/`end_ms` for highlight sync. Separate players for narration / music /
SFX channels. Bedtime profile lowers speed + SFX. When a segment has a bundled `audio_asset` it plays
the file; when absent it falls back to `flutter_tts` (clearly flagged DEV-ONLY, never the child-prod path).

### AR Module (§9.3)

`ArSceneController` abstraction with three implementations chosen at runtime:
`ArKitSceneController` (iOS image tracking), `ArCoreSceneController` (Android augmented images),
`SimulatedArSceneController` (camera preview + animated overlay — used on unsupported platforms /
when no reference image is registered, so the app always runs). All consume the same `ArScene`
(`scene_json`): place `assets[]`, run `default_animation`, and on `tap` interaction fire
`play_audio_segment` against the Audio engine. `story_pages.image_target_id` → reference image;
`ar_scenes.page_id` → scene, per §3.6.

### Safety/privacy enforced in the client (§14)

Microphone off by default; AR camera gated by parent permission; parental gate on settings/dashboard;
no external links, no social, no ads, no autoplay after a story; age-band not birthdate, nickname not
legal name, no child photo. Only consumes pre-authored content (no live generation).

## Verification approach

`flutter analyze` (errors filtered by severity) + `dart run build_runner build` for codegen must pass.
No `flutter run`, no widget/integration tests during development (per user rules). On-device AR
tracking and real narration audio are explicitly deferred to hardware/content follow-ups.

## Out of scope / follow-up slices

Backend API + Postgres; the 6 async workers (TTS, audio mix, AR bundling, image-target gen, safety,
recommendations); content studio + RBAC; real signed-URL CDN asset delivery; activation-code redemption
against a server; classroom mode; localization pipeline.
