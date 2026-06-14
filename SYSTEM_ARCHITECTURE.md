# System Architecture — Detailed Technical Breakdown
## Interactive Storybook Voice + AR App

> Derived from `interactive_storybook_voice_ar_product_technical_spec.md` (v1.0). Section references like (§9.5) point back to that spec.
> Companion diagrams: `system-architecture-diagrams.html` (high-level system, AR pipeline, voice/audio pipeline, content-publishing flow).

---

## 1. Architecture Overview

The Interactive Storybook Voice + AR app turns children's printed and licensed books into narrated, augmented-reality story experiences for children aged 3–8, with parents kept firmly in control. A child opens a curated story or scans a supported physical page; the app reads it aloud in expressive, age-appropriate character voices, brings illustrated characters to life over the page through AR, and asks a few lightweight comprehension questions. The architecture exists to deliver that "the book came alive" moment while honoring two non-negotiable principles that shape every component: **book-first, screen-second** (the app enhances the physical book and stays bounded and calm — no open chat, no infinite feed, no addictive mechanics, §5) and **safety-first / privacy-by-design** (children only ever consume pre-generated, human-reviewed assets, and the system collects the minimum data required to operate, §13.2, §14).

These principles produce one defining technical decision that recurs throughout this document: **all child-facing content is pre-generated, human-reviewed, and served as static assets via CDN behind signed URLs — never generated in real time for the child** (§18.2, §13.2). The system is organized into **four layers** (§9.1): (1) a **mobile client** with five modules (Child Story Player, AR Module, Audio Playback Engine, Offline Cache, Parent Dashboard); (2) a **Backend API** of nine services; (3) a fleet of six **async workers** that run the content-production pipeline; and (4) a shared **data layer** of PostgreSQL, Redis, Object Storage, CDN, and an Analytics Warehouse. The client only consumes approved, locked assets; the workers and admin tooling are where AI-assisted production and the human safety gates live; and the data layer cleanly separates the *content* subtree (authored once, shared by all) from *runtime telemetry* (per child, minimized by design).

---

## 2. High-Level System Architecture

The four layers map onto the topology in §9.1. The connecting idea is a strict separation of *roles*: API services are thin, read-mostly request handlers that read/write PostgreSQL and hand back **signed URLs**; the heavy lifting (TTS, mixing, AR bundling, reference-image database generation, safety classification) is pushed onto async workers; and binary assets are never streamed by the API but downloaded directly from the CDN.

### 2.1 Client (§9.1, §9.2)

The mobile app is composed of five modules (§9.1): **Child Story Player**, **AR Module**, **Audio Playback Engine**, **Offline Cache**, and **Parent Dashboard**. The spec offers three client-stack options (§9.2):

- **Option A — Flutter + Unity AR Module.** Flutter main app; AR via Unity + AR Foundation (targets both ARKit and ARCore); native/Flutter audio engine; offline cache via SQLite/Drift/Hive; analytics via Firebase/PostHog/custom. *Pros:* one main codebase, fast child-friendly UI, Unity strong for animation/AR. *Cons:* larger app size, more complex build pipeline, needs Unity expertise.
- **Option B — React Native + Native AR Modules.** RN main app with native ARKit/ARCore modules, RN Track Player or native audio, SQLite/MMKV cache. *Pros:* fast iteration, strong ecosystem, easier TS code-sharing with admin/web. *Cons:* AR bridge complexity, native performance tuning.
- **Option C — Fully Native (Swift+ARKit / Kotlin+ARCore).** Best AR quality, performance, and camera/audio lifecycle control, but slowest and most expensive — requires two app teams.

**CTO recommendation (§9.2):** for the first six months, use **Flutter or React Native for the main app plus Unity/AR Foundation or native AR for AR scenes** — React Native if the founding team is strong in TypeScript, Flutter if a polished child-friendly UI is wanted quickly. Move more AR logic into Unity/native only if AR becomes the core differentiator.

### 2.2 Backend Services — the 9 services (§9.5)

1. **Auth & Account Service (§9.5.1):** parent login, session management, device management, parental-gate state. Passwordless/OAuth for parents; no independent child login in MVP.
2. **Child Profile Service (§9.5.2):** age band, language, settings, reading preferences, parent-controlled permissions. Data-minimized — nickname not legal name, age band not birthdate, no child photo.
3. **Story Content Service (§9.5.3):** story/page metadata, narration scripts, content availability, age range, localization. Backs `GET /v1/stories` and `GET /v1/stories/{id}` (§11.1–11.2).
4. **Audio Asset Service (§9.5.4):** stores generated audio URLs, manages audio versions, **serves signed URLs**, handles cache invalidation, tracks audio review status.
5. **AR Asset Service (§9.5.5):** stores AR scene metadata and assets, maps page IDs → AR scenes, manages asset-bundle versions, serves device-compatible assets. Backs `GET /v1/stories/{id}/image-target-manifest` (§11.5).
6. **Story Session Service (§9.5.6):** tracks story start/completion, current page, interactions, question answers, resume state. Backs `POST /v1/story-sessions` and `POST /v1/story-sessions/{id}/events` (§11.3–11.4).
7. **Entitlement / Activation Code Service (§9.5.7):** subscription, activation-code unlock, school-license, and publisher-campaign access. Backs `POST /v1/activation-codes/redeem` (§11.6).
8. **Analytics Event Service (§9.1, §16):** ingests product/learning/technical events (story start, completion, scan success, question answered) and forwards them to the Analytics Warehouse.
9. **Admin / Publisher Service (§9.5.8):** content upload, review workflow, rights metadata, publishing workflow, analytics reporting — the backend of the internal Content Studio (§7.3.1).

### 2.3 Async Workers — the 6 workers (§9.1, §18.1)

Triggered off a queue (BullMQ / SQS / Cloud Tasks, §18.1), these run the production pipeline. They read source content and write produced assets to Object Storage and metadata to PostgreSQL; the CDN fronts the finished assets.

1. **Voice Generation Worker:** runs TTS over the narration script (§9.4.1) to produce draft narration audio. This is the *only* component that calls the external TTS API — never the client.
2. **Audio Processing Worker:** volume normalization, sound-effect/music mixing, gapless-segment preparation (§9.4.1, §9.4.3).
3. **AR Asset Processing Worker:** processes/optimizes AR assets and builds device-compatible asset bundles (§7.3.1, §9.3.4).
4. **Image Target Processing Worker:** image-quality validation and reference-image database generation, producing the per-story image-target manifest for page recognition (§9.3.1).
5. **Safety Review Worker:** policy filters + age-appropriateness classification feeding the human editorial review before assets are locked (§13.2).
6. **Recommendation Worker:** computes "suggested next stories" for the parent dashboard (§7.2.2). MVP keeps this rule-based, not ML (§25).

### 2.4 Data Layer (§9.1, §18.1)

- **PostgreSQL** — system of record for all relational entities (§10): `users`, `child_profiles`, `stories`, `story_pages`, `narration_segments`, `ar_scenes`, `story_sessions`, `interaction_events`. All API services read/write here.
- **Redis / Key-Value Cache** — hot-path caching for API responses and session/resume state.
- **Object Storage (S3-compatible)** — binary assets: generated audio, AR asset bundles, page images, reference-image-target metadata. Workers write here; Asset services issue signed URLs against it.
- **CDN (Cloudflare or cloud provider)** — fronts Object Storage to serve audio and AR assets at the edge. §18.2 mandates aggressive CDN use for both.
- **Analytics Warehouse** — destination for events from the Analytics Event Service, used for product/learning/technical metrics (§16) with privacy-preserving aggregation.

### 2.5 Asset Serving — signed URLs + CDN (§9.5.4, §15.2, §18.2)

The asset-serving contract is central and worth stating once for the whole system. The Audio Asset and AR Asset services do **not** stream bytes themselves; they return **signed URLs** (§15.2) pointing at CDN-fronted Object Storage. The client downloads audio and AR bundles **directly from the CDN** — a sync flow separate from the REST API calls — and caches them in the Offline Cache for offline playback (§7.1.7, §9.4.3). Because §18.2 explicitly mandates "pre-generate and cache narration" and "avoid real-time TTS for child sessions," every asset is produced ahead of time by the workers, gated by the Safety Review Worker plus human editorial review (§13.2), and only then published. The child app therefore only ever consumes approved, static assets.

---

## 3. AR Recognition & Scene Pipeline

The AR subsystem spans the server/worker boundary and the device, with the **image-target manifest** (`GET /v1/stories/{story_id}/image-target-manifest`, §11.5) as the handoff between them.

### 3.1 End-to-End Pipeline (§9.3.1)

```
Book page image → Image quality validation → Reference image database generation
  → App downloads image target metadata → Camera detects target page
  → App loads AR scene mapped to page ID
```

The first three stages are **server-side / content-production** (run by the Image Target Processing Worker and AR Asset Service); the last three are **on-device** (the AR Module). The **image quality validation** stage gates the database build — poor source images are rejected before they can break recognition.

### 3.2 Reference-Image Recognition over OCR (§9.3.1)

Reference-image recognition is the **primary** page-detection method, not OCR, because it is faster and more reliable for illustrated pages, works when text is small or stylized (children's books use decorative type), allows a direct page-image → AR-scene mapping, and avoids OCR text-extraction errors. OCR is *not* the matching key; recognition is purely visual feature matching against a pre-built reference-image database. OCR is at most an optional bought capability (§25), never the primary path.

### 3.3 ARKit / ARCore Constraints (§9.3.2, §31)

- **Apple ARKit** detects reference images in an AR session and places content when a known image is detected.
- **Google ARCore Augmented Images** detects and augments 2D images such as posters, packaging, and printed pages.
- ARCore documents practical **reference-image database** and **simultaneous image-tracking limits** (caps on concurrently tracked images and on database size). The spec treats these as **platform constraints to verify during implementation** — the device-side image-target database built from the manifest must stay within per-platform database/tracking limits. This is a known risk to validate, not a fixed number in the spec.

### 3.4 On-Device vs Server Recognition — MVP = On-Device (§11.5)

For MVP, recognition happens **mostly on-device** using the downloaded reference-image metadata. The `image-target-manifest` endpoint delivers that manifest and supports **fallback and content updates** — server-side recognition is a fallback path, not the primary flow. This keeps detection low-latency and offline-tolerant, and underpins the <2 s AR-detection target (§17).

### 3.5 AR Scene Model (§9.3.3, persisted as `ar_scenes.scene_json` JSONB, §10.1)

Each scene is structured data with:

- `scene_id` — unique scene identifier (e.g. `scene_bunny_page_03`).
- `story_id` — owning story.
- `page_id` — the page the scene is bound to; the join key from a recognized image target back to the scene.
- `anchor_type` — `image_target` for MVP (printed-page tracking).
- `assets[]` — each with `asset_id`, `type` (e.g. `2d_character`), `position {x,y,z}`, `scale`, `default_animation` (e.g. `idle_wave`).
- `interactions[]` — each with `trigger` (e.g. `tap`), `target_asset_id`, `action` (e.g. `play_audio_segment`), and `audio_segment_id` linking the tap to a narration/audio segment.

The `ar_scenes` row also carries an independent `status` (`draft`/`review`/`published`/`archived`) so only published scenes ship to devices.

### 3.6 Data Binding (§10.1)

`story_pages.image_target_id` ties a printed page to its reference-image entry; `story_pages.page_image_asset_id` is the source page image fed into the pipeline. `ar_scenes.page_id` → `story_pages.id` resolves a detected page to its AR scene. Once the manifest and scene bundle are cached, *detection → scene lookup → asset render* is a deterministic, on-device join. A mismatched `image_target_id` ↔ `page_id` linkage renders the wrong or no scene.

### 3.7 2D-First Asset Strategy (§7.1.4, §9.3.4)

Start with **2D animated assets, not 3D**: layered 2D characters animated with **Spine, Lottie, Rive, or Unity 2D rig**; a simple animation set (idle, blink, wave, jump, talk, sleep); transparent **PNG/WebP** or vector animation. Rationale: cheaper to produce, matches children's-book illustration style, easier to match publisher art, lower device-performance requirements. 3D is deferred until a story needs it or AR becomes a premium feature.

### 3.8 MVP AR Scope (§7.1.4)

2D animated characters first; **1 hero AR moment per story**; **1–2 interactive objects per scene**; image-target tracking for printed pages only. Deferred: 3D characters, multi-character scenes, spatial room placement, multi-user classroom AR.

**AR failure modes / risks:** reference-image DB size and simultaneous-tracking caps differ across ARKit/ARCore (§9.3.2) — the manifest must be sized per platform; poor page-image quality breaks recognition (mitigated by the validation gate); asset-bundle version skew between manifest and cached scene bundles must be managed by AR Asset Service version control (§9.5.5).

---

## 4. Voice & Audio Pipeline (Production + Playback)

This subsystem has two connected halves: an **offline production pipeline** (server/worker) that turns a manuscript into reviewed, locked audio, and an **on-device playback engine** that consumes only approved, signed audio plus the narration script.

### 4.1 Production Pipeline (§9.4.1, §12.1, §13.2)

```
Story manuscript → Text cleaning → Page segmentation → Character detection / manual assignment
  → Narration script → Voice style assignment → TTS generation → Audio normalization
  → Sound effect mixing → Human review → Publish audio assets
```

- **Text cleaning / page segmentation / character detection** — pre-processing of the raw manuscript. Character detection is AI-assisted but supports **manual assignment** (§7.3.1), aligning with §13.1 use case 1 ("draft narration script").
- **Narration script (§9.4.2)** — the structured artifact from which all audio, subtitles, highlights, and interactions derive (schema below).
- **Voice style assignment (§7.1.3, §13.1)** — assigns `voice_id`, emotion tags (happy, sleepy, surprised, worried), and pacing per speaker. Must use **licensed or platform-approved voices only**.
- **TTS generation** — the **Voice Generation Worker** calls an **external TTS API** (TTS is bought, not built, for quality/speed, §25).
- **Audio normalization** — volume normalization across stories, handled by the **Audio Processing Worker** (§9.4.3, §7.1.3).
- **Sound effect mixing** — narration mixed with music and SFX (music kept lower than narration, SFX used sparingly, §26.4), also an Audio Processing Worker responsibility.
- **Human review gate** — the **Safety Review Worker** / Safety Reviewer (§19.1) gates publication. "All generated narration should be reviewed before publication" (§9.4.4); §13.1 forbids "unreviewed generated audio." This is a hard gate.
- **Publish audio assets** — approved, locked assets go to Object Storage + CDN (§18.2). The Audio Asset Service (§9.5.4) stores URLs, manages versions, serves **signed URLs** (§15.2), handles cache invalidation, and tracks review status.

### 4.2 Narration Script Schema (§9.4.2, mirrored by `narration_segments`, §10.1)

Top-level: `story_id`, `page_id`, `segments[]`. Each segment object maps directly onto a `narration_segments` row:

| Script field | DB column | Notes |
|---|---|---|
| `segment_id` | `id` / `sort_order` | playback order |
| `speaker` | `speaker_key` | narrator vs character |
| `text` | `text` | |
| `voice_id` | `voice_id` | licensed/approved voice ref |
| `emotion` | `emotion` | |
| `speed` | `speed NUMERIC(4,2)` | |
| `start_ms` / `end_ms` | `start_ms` / `end_ms` | gapless playback, highlight sync, AR audio-segment triggers |

The DB row additionally carries `audio_asset_id` (the rendered clip per segment) and `sort_order`. This single structured format intentionally drives audio, subtitles, sentence highlights (§7.1.2), and tap-to-play-segment AR interactions (§9.3.3 `play_audio_segment`).

### 4.3 Why Pre-Generate + Review, Never Real-Time TTS (§13, §18.2, §27.4)

- §18.2: "Pre-generate and cache narration. **Avoid real-time TTS for child sessions.**"
- §13.1 "avoid in MVP": free-form child chatbot, child-directed generative continuation, **unreviewed generated audio**, real-time emotional persuasion, voice cloning.
- §9.4.4: children must not directly prompt the AI voice engine; no emotionally manipulative messages; no unsupervised generated story content.
- §27.4 safety test: "verify no unreviewed generated content appears in child app."

The rationale is the convergence of child safety, a bounded experience, predictable cost/quality, and offline support — all of which require fully baked, reviewed assets rather than live generation.

### 4.4 Voice Safety Constraints (§7.1.3, §9.4.4)

No celebrity voice imitation; no user/parent/child voice cloning in MVP (also a non-goal, §8.4); no realistic impersonation of relatives (only with future explicit consent + safety controls); licensed or platform-approved voices only; no emotionally manipulative or persuasive narration.

### 4.5 Playback (On-Device) (§9.4.3, §7.1.x, §9.1)

The **Audio Playback Engine** pulls the narration script (via Story Content Service / `GET /v1/stories/{story_id}`, §11.2) and **signed audio URLs** (from Audio Asset Service, §9.5.4 / §15.2). Requirements (§9.4.3):

- **Gapless segment playback** — driven by `start_ms`/`end_ms` ordering.
- **Resume from last page** — also `story_sessions.last_page_number` (§10.1).
- **Preload next page audio** — to hit the <1 s cached audio-start target (§17).
- **Volume normalization across stories** — relies on production-side normalization.
- **Separate channels for narration, music, and SFX** — independent on-device mixing (§26.4).
- **Bedtime audio profile** (§7.1.6, §6.3) — slower narration, lower SFX, warmer audio; `bedtime_mode_default` in `child_profiles`.
- **Offline playback** (§7.1.7) — downloaded audio + page metadata served from the Offline Cache; "offline story open < 1 s" (§17).

**Audio failure modes / risks:** "TTS quality not emotional enough" (§23) — mitigated by exactly this pipeline (pre-generate, review, sound design, curated voices); skipping review could leak unreviewed audio to children — blocked by the §13.2 gate and §27.4 test; a missing/expired signed URL or empty offline cache breaks playback — mitigated by the offline cache + resume state.

---

## 5. Content Production & Publishing Flow

This subsystem governs how a book becomes a child-safe interactive asset and how it is gated through human review before reaching the child app. It is the operational spine that connects production (Sections 3–4) to playback.

### 5.1 Full Content Workflow (§12.1)

A linear, gated sequence:

1. Acquire rights / create story — rights metadata must exist from the start (§7.3.2).
2. Upload manuscript and page images (§7.3.1, §6.5).
3. Segment story by page; assign speakers and voices (§7.3.1).
4. Generate narration draft — AI-assisted (§9.4.1, §13.1 use case 1).
5. Add sound effects and music (§9.4.1).
6. Create AR hero moment — 1 per story for MVP (§7.1.4, §8.2); AR scene ideas may be AI-drafted (§13.1 use case 6).
7. Add comprehension questions — 3 per story (§7.1.5, §8.2; AI-suggested, §13.1 use case 3).
8. Safety and editorial review (§12.1, §12.2).
9. Device QA (§12.1).
10. Publish to staging, then production (§7.3.1).

### 5.2 Publishing State Machine and the Enum Mapping (§19.2, §10)

The operational state machine is:

```
Draft → Internal Review → Safety Review → Device QA → Published → Archived
```

The spec carries two related but distinct enums, and the architecture must reconcile them deliberately: the **six-state operational model** (§19.2) and the narrower **DB `content_status` / `ar_scenes.status` enum** (§10) with four values — `draft`, `review`, `published`, `archived`. The DB collapses *Internal Review + Safety Review + Device QA* into the single `review` value. The six-state machine is the operational truth; the four-value enum is its persisted approximation. **Enum drift** is a real risk: the Device-QA / Internal / Safety distinctions can desync if the mapping is not maintained explicitly.

### 5.3 AI Drafts Gated by Human Review (§13.2, §13.1, §9.4.4)

AI assists production but never reaches the child directly. The §13.2 safety chain is:

```
AI draft generation → Policy filters → Age appropriateness classifier
  → Human editorial review → Locked production assets → Child app only consumes approved assets
```

AI-generated artifacts — draft narration script, suggested character voices, suggested comprehension questions, AR scene ideas, localization drafts, pronunciation review (§13.1 use cases 1–7) — feed the Content Studio **as drafts only**. Two automated gates run first (policy filters, age-appropriateness classifier), but the **binding gate is human editorial / Safety Review**. The child app consumes only **locked production assets** and "should not generate arbitrary story content live for the child" (§13.2).

### 5.4 Human Review Checklist (§12.2)

Every story is reviewed across 11 dimensions before it can advance: age appropriateness; language simplicity; cultural sensitivity; emotional tone; scary/intense scenes; voice quality; audio pronunciation; AR animation behavior; question quality; rights metadata; privacy impact. This checklist is the gating criteria for the Safety Review gate; §27.4 independently verifies that no unreviewed generated content reaches the child app.

### 5.5 Roles, Least Privilege, Audit (§19.1, §19.3, §15.4)

Six roles with distinct permissions (§19.1):

- **Content Editor** — upload stories, edit scripts (owns Draft).
- **Audio Producer** — generate and review voice assets.
- **AR Designer** — upload AR scenes and animations.
- **Safety Reviewer** — approve child-facing content (sole approver at the Safety Review gate).
- **Publisher Admin** — view publisher-owned content and reports (read/report scope, not an approver).
- **System Admin** — manage users, roles, infrastructure settings.

Least-privilege requirements (§15.4): admin MFA, least-privilege access, role separation, and **manual approval required before publishing child-facing content**; RBAC is enforced at the API layer (§15.2). The audit trail (§19.3) records who uploaded, who generated audio, who approved safety, who published, which version is live, and which rights are attached.

### 5.6 Publishing-State Guarantees & Environments (§18.3, §15.4)

Hard guarantee: "content should never go directly from draft to production without review" (§18.3) and "manual approval required before publishing child-facing content" (§15.4). Three environments back this (§18.3): **Staging**, a dedicated **Content Review environment**, and **Production** (plus local dev). Production and staging data are kept separate (§15.3); content publishing is separated from app-serving APIs (§18.2); and feature flags gate content rollout (§18.2). Published content can later move to Archived; expired-rights content is auto-disabled (§7.3.2).

### 5.7 Rights, Activation Codes, and Entitlement Gating (§7.3.2, §7.3.3, §9.5.7, §11.6)

**Rights Management (§7.3.2)** tracks content owner, territory rights, language rights, audio rights, AR/digital adaptation rights, and license expiry, and auto-disables expired content. Rights metadata is attached at acquisition and audited (§19.3); `stories` carries `rights_owner_id` and `content_status` (§10).

**Activation Codes (§7.3.3)** support campaign codes, single-use or multi-use types, expiry dates, publisher reporting, and fraud detection. Codes/QR are printed inside physical books (§21.2).

The **Entitlement / Activation Code Service (§9.5.7)** is the access gate between published content and the child app: subscription, activation-code unlock (`POST /v1/activation-codes/redeem`, e.g. `BOOKY-ABCD-1234`, §11.6), school-license, and publisher-campaign access. The library response carries `is_unlocked` per story (§11.1), and premium/publisher-code stories stay locked until entitled (§7.1.1). Content access therefore requires **both** (a) the story reaching `Published` via the review gates, **and** (b) a valid entitlement.

**Content-flow failure modes / risks:** review-gate bypass (mitigated by the separate review environment + manual approval + audit, and tested by §27.4); AI hallucination / unsafe drafts (mitigated by policy filters + age classifier + human review); expired/over-territory rights served (mitigated by rights metadata + auto-disable); activation-code fraud/replay (mitigated by single-use codes, expiry, fraud detection); enum drift (§5.2); and MVP throughput being human-bound, since the Content Studio is internal-only with manual upload/review and no self-serve publisher portal at launch (§7.3.1, §8.3).

---

## 6. Cross-Cutting Concerns

### 6.1 Data Model — ERD in Prose (§10)

A PostgreSQL relational schema rooted at the parent account, fanning out into *content* (authored once, shared) and *runtime telemetry* (per child). All primary keys are `UUID`; timestamps are `TIMESTAMPTZ DEFAULT now()`. Relationships are one-to-many unless noted.

- **`users`** — parent account; the consent/ownership root. `id` (PK), `email` (UNIQUE), `auth_provider`, timestamps. No child PII. One `users` row owns many `child_profiles`.
- **`child_profiles`** — `user_id` → `users(id)` (FK, the only link to a real person). `nickname` (not legal name), `age_band TEXT CHECK IN ('3-4','5-6','7-8')` (band, not birthdate), `language_code` (default `'en'`), and parent-controlled flags `bedtime_mode_default` (default false), `microphone_enabled` (default **false** — off by default), `ar_enabled` (default true). One profile has many `story_sessions`.
- **`stories`** — content-catalog entity, independent of any user. `title`, `slug` (UNIQUE), `description`, `age_min`/`age_max`, `language_code`, `duration_seconds`, `cover_asset_id`, `content_status CHECK IN ('draft','review','published','archived')` (publishing-lifecycle gate, cf. §15.4/§19.2), `rights_owner_id`. Parent of many `story_pages`, `narration_segments`, `ar_scenes`, and `story_sessions`.
- **`story_pages`** — `story_id` → `stories(id)`. `page_number`, `page_text`, `page_image_asset_id`, `image_target_id` (links to the AR reference-image target, §9.3.1 / §11.5). One page has many `narration_segments` and zero-or-more `ar_scenes`.
- **`narration_segments`** — two FKs: `story_id` → `stories(id)` and `page_id` → `story_pages(id)`. `speaker_key`, `text`, `voice_id`, `emotion`, `speed NUMERIC(4,2)`, `audio_asset_id` (rendered audio, served via signed URL, §9.5.4), `start_ms`/`end_ms` (timing/sync), `sort_order NOT NULL` (playback order). This is the persisted form of the §9.4.2 narration-script JSON.
- **`ar_scenes`** — two FKs: `story_id` → `stories(id)` and `page_id` → `story_pages(id)`. `scene_json JSONB` (the §9.3.3 structured scene — anchor, assets, interactions), `status CHECK IN ('draft','review','published','archived')` (independent review lifecycle). One page → AR scene(s).
- **`story_sessions`** — runtime telemetry; FKs `child_profile_id` → `child_profiles(id)` and `story_id` → `stories(id)`. `started_at`, `completed_at` (NULL until finished — completion metric, §16.1), `last_page_number` (resume state, §9.5.6), `mode CHECK IN ('library','scan','bedtime','classroom')`. One session has many `interaction_events`.
- **`interaction_events`** — `story_session_id` → `story_sessions(id)`. `event_type` (e.g. `question_answered`, §11.4), `page_id` (UUID, denormalized — no FK constraint declared in the spec), `payload JSONB` (e.g. `question_id`/`answer_id`/`is_correct`), `created_at`. The leaf telemetry table feeding analytics (§16).

**Shape.** A star/tree: `users → child_profiles → story_sessions → interaction_events` is the user/telemetry spine; `stories → {story_pages, narration_segments, ar_scenes}` is the content subtree; both subtrees join only at `stories` and `child_profiles`. Child telemetry never reaches content tables except by FK to `stories`/`child_profiles`. Asset references (`cover_asset_id`, `page_image_asset_id`, `audio_asset_id`, `image_target_id`) are UUID columns pointing at object storage / asset services (§9.5.4–§9.5.5), not FK-constrained tables in §10. There are deliberately **no social/UGC tables** — a structural reflection of the safety-by-design stance (§14.5).

### 6.2 Privacy & Compliance (§14, §9.5.2, §7.2.1)

Privacy is a core product requirement, not a legal afterthought (§14 intro; principle §5.5).

- **Data minimization, enforced in schema:** age **band** not birthdate (`age_band` CHECK), nickname not legal name, no child photo (§14.1, §14.3, §9.5.2). The §14.3 child-data table marks Voice recordings = **No**, Camera frames = **No** (process on-device), Location = **No**.
- **No raw sensor capture by default:** do not store raw child voice; do not store camera frames (processed on-device, §14.1/§14.3; §27.4 verifies "camera frames are not uploaded by default"). Microphone is disabled by default and gated (`microphone_enabled` default false).
- **No profiling / no ad-tech on children:** no selling child data, no targeted advertising, no public child profiles, no public exposure of activity (§14.1, §14.5, §16.4).
- **Parental consent surface (§14.2):** explicit consent for account creation, child-profile creation, camera/AR usage, microphone usage, data storage, analytics beyond strictly necessary operations, and school-account usage — mapping to the `child_profiles` flags and the parental gate (§7.2.3).
- **Regulatory awareness (§14.4, §31):** consult legal counsel per market before launch — US **COPPA** (under-13 directed services), EU **GDPR** child consent (Art. 8), UK **Age Appropriate Design Code**, Vietnam **Decree 13/2023/ND-CP** children's data rules, plus school/education rules. Treated as awareness requirements, not implemented controls.
- **Safety-by-design (§14.5):** no public comments, no DM, no child-to-child chat, no open web/external links in child mode, no personalized ads, no manipulative streak mechanics, no dark patterns around purchases, no infinite autoplay, no scary AR by default — reinforcing the "bounded, calm" principle (§5.3–§5.4).

### 6.3 Security (§15, §9.5.1)

- **Account (§15.1):** parent-only authentication — no independent child login in MVP (§9.5.1 recommends passwordless/OAuth); secure session tokens; device-level logout; rate limiting on auth endpoints; optional parent MFA.
- **API (§15.2):** TLS everywhere; JWT or session-based auth; **role-based access control**; **signed URLs for private assets** (audio/AR, consistent with §9.5.4); request/input validation; **audit logs for admin actions**.
- **Data (§15.3):** encrypt sensitive data at rest; encrypt backups; minimize logs containing personal data (ties to §14 minimization); retention policy; separate production and staging data (cf. §18.3); regular access review.
- **Admin (§15.4):** admin MFA; least-privilege access; content-publishing audit trail; role separation (editor / reviewer / publisher admin / system admin, full matrix §19.1); manual approval before publishing child-facing content (the `content_status`/`status` draft→published gates in §10 and the §19.2 state machine).

### 6.4 Analytics (§16)

Three metric families, sourced primarily from `story_sessions` and `interaction_events` (§10):

- **Product (§16.1):** story start rate, completion rate, repeat rate, parent return rate, scan success rate, AR interaction rate, bedtime-mode usage, activation-code redemption (start/complete derive from `started_at`/`completed_at`; `mode` distinguishes bedtime/scan/classroom).
- **Learning (§16.2):** questions answered, question accuracy, vocabulary exposure, comprehension completion, future repeated-vocabulary recall — derived from `interaction_events.payload` (e.g. `is_correct`, §11.4).
- **Technical (§16.3):** crash-free sessions, app launch time, audio start latency, audio buffering rate, AR detection latency, AR session FPS, asset download success rate, API p95 latency — aligning 1:1 with the §17 targets and feeding observability (OpenTelemetry, §18.1).
- **Privacy-preserving aggregation (§16.4):** prefer aggregated analytics; avoid detailed behavioral profiling of individual children; give parents clear controls and transparency — the analytics-side enforcement of §14.1's no-profiling stance, itself consent-gated (§14.2). MVP must-have events (§8.3): story start, completion, scan success, question answer.

### 6.5 Performance Targets (§17)

Internal targets, to be validated during development; each pairs with a §16.3 metric. They reflect the architecture's caching bias — pre-generated narration, CDN-served assets, no real-time TTS in child sessions, on-device AR detection.

| Area | Target | Related metric (§16.3) |
|---|---|---|
| App cold start | < 3 s on mid-range device | App launch time |
| Story audio starts (cached) | < 1 s after tapping play | Audio start latency |
| AR page detection | < 2 s under normal lighting | AR detection latency |
| Story page transition | < 500 ms | — |
| Crash-free sessions | > 99.5% | Crash-free sessions |
| Audio buffering | < 1% of sessions | Audio buffering rate |
| Offline story open | < 1 s | Asset download / offline path |
| Admin audio generation preview | < 2 min for short story draft | (admin-side, §7.3.1) |

---

## 7. Key Architectural Decisions & Trade-offs

- **Client stack — Flutter/React Native + Unity/AR Foundation or native AR (§9.2).** Chosen for cross-platform development speed and a polished child UI in the first six months, accepting larger app size / build-pipeline complexity over the slower, costlier fully-native path. Native AR is held in reserve for if AR becomes the core differentiator. *Trade-off:* iteration speed and one codebase now, versus best-in-class AR performance later.
- **Reference-image recognition over OCR (§9.3.1, §25).** Visual feature matching against a pre-built reference-image database is faster and more reliable on illustrated pages, tolerates stylized/small text, and maps page → scene directly, avoiding OCR extraction errors. *Trade-off:* requires a server-side image-quality validation + database-generation step and per-platform DB sizing; OCR is at most an optional fallback.
- **Pre-generated audio over real-time TTS (§18.2, §13).** All narration is produced offline, reviewed, mixed, and cached. This guarantees safety (nothing unreviewed reaches a child), bounds the experience, makes cost/quality predictable, and enables offline playback and the <1 s cached audio-start target. *Trade-off:* no live/dynamic narration and a human-bound production throughput, accepted as the price of safety and offline support.
- **Human-in-the-loop content gating (§13.2, §15.4, §18.3).** AI drafts pass policy filters and an age-appropriateness classifier, but a human Safety Reviewer is the binding approver before assets lock; content never moves draft → production without review. *Trade-off:* slower, human-bound publishing throughput in exchange for parent trust and child safety — explicitly chosen over automation.
- **On-device AR recognition (§11.5).** Page detection runs on-device from the downloaded image-target manifest, keeping latency low and the flow offline-tolerant; the server endpoint is fallback/update only. *Trade-off:* must respect per-platform tracking/database limits and manage manifest/bundle version skew, in exchange for resilience and the <2 s detection target.
- **Data minimization by design (§14, §9.5.2).** Age band not birthdate, nickname not legal name, no child photo, no stored raw voice or camera frames, microphone off by default, no social/UGC tables. *Trade-off:* less behavioral richness for personalization/analytics, deliberately accepted to reduce compliance exposure (COPPA/GDPR/AADC/Decree 13) and earn parent trust.

---

## 8. Risks & Open Questions

### 8.1 Architecture-Relevant Risks (§23)

| Risk | Impact | Mitigation |
|---|---|---|
| Copyright issues | High | Licensed/original/public-domain content first; rights metadata + auto-disable of expired content (§7.3.2) |
| Child privacy compliance | High | Privacy-by-design, parental consent, data minimization (§14) |
| AR unstable on devices | Medium | Simple image targets, supported-device list, on-device detection (§9.3.1, §11.5) |
| Content production expensive | High | 2D assets first, reusable templates, internal studio pipeline (§9.3.4, §7.3.1) |
| App becomes too stimulating | Medium | Bedtime mode, calm design, no infinite feed (§7.1.6, §14.5) |
| Parents distrust AI for kids | High | Human-reviewed content, transparent controls, no open chat (§13.2) |
| TTS quality not emotional enough | Medium | Pre-generate, review, mix sound design, use curated voices (§9.4) |
| App size becomes large | Medium | CDN asset streaming, optional/lightweight downloads, 2D-first AR (§18.2, §9.3.4) |
| Children use app without parent controls | High | Parental gate and restricted child mode (§7.2.3) |

Additional internal risk surfaced by this architecture: **enum drift** between the six-state operational publishing model (§19.2) and the four-value DB `content_status`/`ar_scenes.status` enum (§10) — mitigated by maintaining an explicit, single mapping (see §5.2).

### 8.2 Architecture-Relevant Open Questions (§29)

1. **Physical vs digital books, or both (§29 Q7).** Determines whether the AR scan pipeline (Section 3) is core or secondary, and how heavily the image-target manifest path is invested in.
2. **How much AR quality is needed for the first paid pilot (§29 Q5).** Drives the client-stack decision (Flutter/RN + AR Foundation vs deeper native/Unity AR) and the 2D-vs-3D asset roadmap.
3. **Primary channel — parent app, school, or publisher partnership (§29 Q2).** Shapes which services and modes (classroom mode, activation codes, school licensing in the Entitlement Service) are hardened first.
4. **Original content vs licensing existing books first (§29 Q3).** Determines how much weight the Content Studio, rights-management, and activation-code subsystems carry at launch.
5. **Which market launches first / which legal markets at launch (§29 Q1, Q9).** Directly sets the compliance surface (COPPA / GDPR Art. 8 / UK AADC / Vietnam Decree 13) the privacy and consent architecture must satisfy (§14.4).
6. **Acceptable cost per interactive story (§29 Q8).** Bounds the production pipeline's automation-vs-human-review balance and the achievable content throughput given the human-gated flow.
