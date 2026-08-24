# Storybook AR Redesign (EN + VI) — Design

Date: 2026-08-24
Source designs: Stitch project `8672093703664375909` ("Wireframe to Stitch Design"), design systems **Storybook AR** (light, `assets/21a7a9aeb3a14e35a6d11a17219c501c`), **Midnight Library** (dark/Moon Mode, `assets/c26a879b8c034e74a59ee17708bbd4cc`). Screen HTMLs cached at `/var/folders/qm/kt77dh753zb_x3k1fcp_3xfc0000gq/T/opencode/stitch/`.

## Goal

Apply the new "Storybook AR / Mọt Nhí" design to the Flutter app: rebuild every designed screen to match the Stitch mockups and support English + Vietnamese from one codebase.

Decisions made with the user:

1. Scope = all designed screens; missing screens (Onboarding, Scan Any Page, Story Composer, Parental Gate) are generated in Stitch first.
2. Language coverage = full EN+VI parity (10 additional Stitch screens; My Books & Settings get EN versions).
3. Locale = system default with a manual override persisted on the Settings screen.
4. Fonts = bundled TTFs (no google_fonts runtime dependency).
5. Approach = single codebase with ARB localization (not per-language screen copies).

## 1. Design tokens (`lib/core/theme/`)

Replace `AppTheme` contents with tokens extracted from the design systems.

### Light (Storybook AR)

| Token | Hex |
|---|---|
| background | `#fff8f5` |
| canvas | `#f2eae0` |
| paper | `#fffaf4` |
| surface containers | low `#fef1ec`, `#f8ebe6`, high `#f2e6e1`, highest `#ece0db` |
| ink (on-surface) | `#201a18` |
| ink-muted | `#746b66` |
| coral primary action | `#dc704b` |
| coral pressed (button underside) | `#b95639` |
| primary container | `#9b3f1e` |
| lavender secondary | `#63539e`, container `#bfadff` |
| sage tertiary | `#3b644c`, container `#547e63` |
| gold | `#f2d493` |
| line | `#dbd0c4` |
| error | `#ba1a1a` |

### Dark (Midnight Library / Moon Mode)

| Token | Hex |
|---|---|
| background | `#140f2a`, surface `#27223e`, container `#332c4c` |
| on-surface | `#e6e1f3`, variant `#c9c2e0` |
| primary action | `#e38a6a`, on-primary `#5d1800` |
| lavender text | `#dcd6f7` |
| off-white story text | `#f5f5f7` |
| outline | `#5a527a` |

### Shape / spacing / elevation
- Card radius 22px; pills 999px; inputs 14px; book covers asymmetric `42/42/22/22`.
- Spacing scale: page-h 28px, page-v 36px, section gap 42px, element gap 16px, min touch target 44px.
- Warm shadow `0 18px 40px rgba(76,57,43,0.15)` instead of grey shadows; glassmorphism only for the floating bottom nav and AR overlays.

### Typography (bundled)
- Source Serif 4: 400/600/700 → headlines, story text (20px/1.6), titles.
- Nunito Sans: 400/700/800 → body UI (14px), buttons (13px w800), eyebrows (12px w800, tracked 0.05em uppercase), pill labels.
- Registered under families `SourceSerif4` and `NunitoSans`; mapped into `ThemeData.textTheme`.

### Shared widgets (`lib/shared/widgets/storybook/`)
Built once, reused everywhere:
- `PressablePillButton` (primary: coral fill + 4px `coral-pressed` bottom border + press translate; secondary: line border)
- `ProgressBeads` (active coral / inactive line)
- `FloatingNavBar` (glass blur paper tint, Stories / My books / Moon mode)
- `PaperCard` (22px radius, warm shadow)
- `EyebrowLabel`
- `StoryCover` (asymmetric radius, progress beads slot)
- Moon-mode-aware via `Theme.of(context)` only — no per-widget branching.

## 2. Localization

- Add `flutter_localizations` (sdk) to `pubspec.yaml`; configure `generate: true` + `l10n.yaml` (`arb-dir: lib/l10n`, template `app_en.arb`).
- `app_en.arb` / `app_vi.arb` carry every UI string for all screens (existing hardcoded strings included).
- `StorybookApp` gains `locale` from a new `localeOverrideProvider` (null ⇒ system). Override picker lives on Settings; persisted through `KeyValueStore`.
- Story content language stays driven by child profile (`languageCode`) as today; this work localizes *UI chrome* only.

## 3. Navigation & screens

Routes (go_router) after redesign:

| Route | Widget | Notes |
|---|---|---|
| `/onboarding` | `OnboardingScreen` | redesigned: eyebrow, serif headline, privacy copy, nickname input card, age pills (3–4/5–6/7–8), language pills, AR + mic toggles (mic off), consent checkbox, Start reading CTA |
| `/home` | `ChildHomeScreen` (replaces `LibraryScreen`) | greeting + Parent Area chip → gate; "Jump back in" hero (last position, Resume); "For you" chips (Animals/Friends/Bedtime); story grid cards (age pill + minutes); floating nav |
| `/my-books` | `MyBooksScreen` | NEW: filter chips Downloaded/Favorites/Reading; RECENT row of covers with % read; explore promo card; same floating nav |
| `/story/:id/detail` | `StoryDetailScreen` | NEW intermediate before player: back/more bar, cover hero, chips (ages · minutes · bedtime), synopsis, AR callout card, Read story CTA, "Download for later" secondary renders visually but is inert until offline downloads ship (out of scope) |
| `/story/:id/read` | `StoryPlayerScreen` (route changes from `/story/:id`) | rebuilt chrome: title bar with page beads "Page n of m", dark-mode quick toggle, AR-surprise banner, serif story text, replay/prev/play/next row, "Magic Spark" AR button. Playback/AR logic unchanged |
| `/parent` | `ParentDashboardScreen` | weekly stats header, gentle summary (stories finished, questions explored), most-recently-read resume row, links: Reading & safety settings, My books |
| `/parent/settings` | `SettingsScreen` | rebuilt per mockup: reading-time-limit pills (15/45/120 min), content-filter bands (Preschool 2–5 / Primary 6–9 / Explorer 10+), notifications toggle, Account row, Save button; plus App language picker (English/Tiếng Việt). Existing bedtime-mode toggle remains |
| `/gate` | `ParentalGateScreen` | restyled: gold lock circle, serif math question, big numeric field, Continue pill |
| `/scan-any-page` | `ScanAnyPageScreen` | restyled entry/review/progress states with new components; SCAN→VOICE→CHARACTER beads stepper |
| `/create-story` | `StoryComposerScreen` | restyled: name card, captured-page rows, dashed add-page card, sticky Save pill |

Behavioral notes:
- Home → story tap now routes to `/story/:id/detail`; Read story → player.
- Bottom-nav "Moon mode" toggles `bedtimeModeProvider` (same as today's settings toggle).
- Parent Area chip on Child Home goes through `/gate` redirect as today (guard unchanged).
- Deleting authored stories stays gated on the parent dashboard.

## 4. Data & error handling

No repository/provider/API changes. Presentation-only refactor. Empty/error states reuse `PaperCard` + beads. Player narration, AR channel, scan/TTS flows keep their controllers untouched except for widget bindings.

## 5. Testing

- Update widget tests that reference removed/renamed screens (`LibraryScreen` → `ChildHomeScreen`, player route).
- New smoke tests per rebuilt screen; run key flows under both locales by injecting `Locale('vi')`.
- `flutter analyze` must pass; `flutter test` green.

## 6. Out of scope

- Backend, models, repositories, AR native layer, narration pipeline.
- Desktop landing pages in Stitch (marketing site, not app screens).
- New features implied but not built in app (account management, notifications delivery, reading-time enforcement) — Settings renders the controls; persistence/wiring lands in later slices where noted.

## 7. Pending Stitch generations (non-blocking)

Created so far: Onboarding (EN) `2ccaf54734354886a3b88926979bd769`, Parental Gate (EN) `adc0e96bd9034e408401d0364db83791`.
Still queued due to service timeouts: Scan Any Page EN/VI, Story Composer EN/VI, My Books EN, Settings EN, Onboarding VI, Gate VI. Their prompts are fully specified in session history; because all text lives in ARB files and layouts follow established component patterns, implementation proceeds without them; reconcile visuals when generation succeeds.
