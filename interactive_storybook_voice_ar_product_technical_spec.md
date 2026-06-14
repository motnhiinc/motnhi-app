# Interactive Storybook Voice + AR App

**Product & Technical Specification**  
**Audience:** Children aged 3–8, parents, schools, and children's book publishers  
**Document owner:** CEO/CTO draft  
**Version:** 1.0  
**Date:** 2026-06-10

---

## 1. Executive Summary

This document defines the product and technical direction for a mobile app that transforms children's books into narrated, interactive, augmented-reality story experiences.

The product is not positioned as a generic text-to-speech utility. The stronger positioning is:

> **An interactive storybook platform that makes children's books speak, perform, and come alive through AI voice and AR.**

The core user experience is simple:

1. A parent opens the app.
2. The child chooses a book or scans a physical page.
3. The app reads the story aloud using expressive, age-appropriate voices.
4. Characters appear on the page through AR.
5. The child taps, listens, answers lightweight questions, and learns through interaction.

The most important product principle is that the child experience must be **bounded, safe, and calm**. The app should avoid open-ended AI chat, addictive mechanics, social features, targeted advertising, and unnecessary data collection.

The strongest go-to-market wedge is not “upload any book and generate audio.” That path creates legal, quality, and safety risks. The better wedge is a **licensed interactive library** and **publisher partnership model**, where each supported book has controlled narration, approved AR assets, and child-safe interactions.

---

## 2. Product Vision

### 2.1 Vision Statement

To make reading more magical, accessible, and engaging for children by turning books into interactive voice and AR experiences while keeping parents in control.

### 2.2 Product Promise

For children:

> “Your storybook friends can speak, move, and play with you.”

For parents:

> “A safe, educational, screen-light reading companion that makes children more excited about books.”

For schools:

> “A classroom reading tool that combines storytelling, language learning, and guided interaction.”

For publishers:

> “A digital layer that increases the value of printed children's books without replacing the book itself.”

---

## 3. Strategic Positioning

### 3.1 Category

The product sits between four categories:

1. Children's audiobook apps
2. Interactive learning apps
3. AR book experiences
4. AI-assisted content creation platforms for publishers

The winning position is:

> **Voice-first AR reading companion for children's books.**

This is stronger than “AI audiobook app” because the product extends the physical book instead of replacing it.

### 3.2 Differentiation

| Existing Alternative | Limitation | Product Differentiation |
|---|---|---|
| Standard audiobooks | Passive listening only | Interactive page-level narration and AR |
| YouTube kids content | Distracting and algorithmic | Book-based, parent-controlled, calm UX |
| Generic TTS apps | Robotic, not story-aware | Character voices, sound design, narration pacing |
| AR toy apps | Often gimmicky | AR tied directly to reading comprehension |
| E-book apps | Replace printed books | Enhances printed books through scan-to-read |

### 3.3 Core Product Thesis

Children do not only need more screen content. They need better reading rituals. The product should use AI and AR to strengthen the book-reading habit, not replace it.

---

## 4. Target Users

### 4.1 Primary User: Parent of Child Aged 3–8

**Needs:**

- Help child enjoy reading.
- Reduce dependence on passive video content.
- Support bedtime reading.
- Support early language development.
- Keep screen experience safe and controlled.

**Pain points:**

- Children get bored with static books.
- Parents do not always have time or energy to read expressively.
- Audiobooks are not interactive.
- Many children's apps are overstimulating.

**Success criteria:**

- Child asks to read again.
- Parent trusts the app.
- App becomes part of bedtime or weekend routine.

### 4.2 Secondary User: Child Aged 3–8

**Needs:**

- Fun characters.
- Simple interactions.
- Clear voice.
- Immediate feedback.
- Visual delight.

**Design requirements:**

- Large touch targets.
- Minimal text navigation.
- Audio-first interface.
- No complex menus.
- No open internet access.
- No social sharing.

### 4.3 Buyer Segment: Kindergarten / Primary School

**Needs:**

- Classroom reading engagement.
- Language learning support.
- Teacher-controlled story sessions.
- Group mode and lesson mode.

**Success criteria:**

- Teacher can launch a story in under 60 seconds.
- Children remain engaged.
- Teacher receives simple learning feedback.

### 4.4 Partner Segment: Children's Book Publisher

**Needs:**

- Increase printed book value.
- Add digital experience without building a full app.
- Sell premium editions or activation-code editions.
- Protect intellectual property.

**Success criteria:**

- App increases book sales or retention.
- Publisher can onboard books with predictable cost.
- Rights and usage are auditable.

---

## 5. Product Principles

1. **Book-first, screen-second**  
   The screen should enhance the book, not compete with it.

2. **Parent in control**  
   Parents should manage profiles, reading time, content, voice, and privacy.

3. **Bounded child interaction**  
   Children should interact through guided choices, taps, and safe prompts. Avoid open-ended AI chat in the MVP.

4. **Calm by default**  
   Avoid overstimulating animations, infinite feeds, streak pressure, and aggressive gamification.

5. **Privacy by design**  
   Collect the minimum data required to operate the product. Avoid targeted advertising and behavioral profiling of children.

6. **Licensed content first**  
   Prioritize licensed books, original stories, or public-domain content. Do not depend on unauthorized scanning of commercial books.

7. **Offline-friendly**  
   Children may use the app during travel or bedtime. Pre-download audio and AR assets where possible.

---

## 6. Core Use Cases

### 6.1 Use Case A: Read From App Library

**User:** Parent and child  
**Flow:**

1. Parent opens the app.
2. Child selects a story from the library.
3. App starts narration.
4. Character voices and sound effects play.
5. AR moments appear at selected pages or scenes.
6. App asks simple comprehension questions.
7. Parent sees reading summary.

**MVP priority:** High

### 6.2 Use Case B: Scan Physical Book Page

**User:** Parent and child  
**Flow:**

1. Parent selects “Scan Book.”
2. Camera opens.
3. App detects a supported page using image recognition.
4. App loads the correct narration and AR scene.
5. Child watches the character appear over the page.

**MVP priority:** High for demo; medium for production if library mode launches first.

### 6.3 Use Case C: Bedtime Mode

**User:** Parent  
**Flow:**

1. Parent selects a story.
2. Parent turns on Bedtime Mode.
3. App uses slower narration, reduced animation, warmer audio, and lower brightness.
4. Story ends without autoplay into more content.

**MVP priority:** High

### 6.4 Use Case D: Classroom Reading Mode

**User:** Teacher  
**Flow:**

1. Teacher opens classroom mode.
2. Teacher selects story and age group.
3. App presents story on tablet or cast screen.
4. Children answer as a group or through teacher-guided prompts.
5. Teacher receives simple engagement metrics.

**MVP priority:** Medium

### 6.5 Use Case E: Publisher Uploads a Book

**User:** Publisher or internal content operator  
**Flow:**

1. Publisher uploads book pages and manuscript.
2. Content team segments pages and assigns characters.
3. AI generates draft narration.
4. Human reviewer approves voices, timing, safety, and AR scenes.
5. Book is published with activation code or library access.

**MVP priority:** Medium for internal tooling; high for long-term scale.

---

## 7. Feature Specification

## 7.1 Child App Features

### 7.1.1 Story Library

**Description:**  
A curated library of available stories.

**Capabilities:**

- Browse by age group: 3–4, 5–6, 7–8.
- Browse by theme: animals, bedtime, friendship, emotions, language learning.
- Show downloaded/offline stories.
- Display parent-approved stories only.
- Lock premium or publisher-code stories.

**MVP requirement:**

- 5–10 demo stories.
- Static categories.
- Download state.
- Story cover, title, duration, age range.

### 7.1.2 Story Player

**Description:**  
The main reading interface.

**Capabilities:**

- Play/pause narration.
- Page navigation.
- Highlight current sentence or page.
- Character voice switching by segment.
- Sound effects and background music.
- Replay page.
- “Read to me” and “Read together” modes.

**Child UX requirements:**

- Large play button.
- Minimal controls.
- No external links.
- No ads.
- No social buttons.

### 7.1.3 Character Voices

**Description:**  
Each story can include different voices for narrator and characters.

**Capabilities:**

- Narrator voice.
- Character-specific voice styles.
- Emotion tags such as happy, sleepy, surprised, worried.
- Pacing control.
- Volume normalization.
- Optional multilingual narration.

**Safety requirements:**

- No celebrity voice imitation.
- No user voice cloning for MVP.
- No realistic impersonation of relatives unless future explicit consent and safety controls exist.
- Use licensed or platform-approved voices only.

### 7.1.4 AR Story Mode

**Description:**  
Characters and objects appear over the book page or physical environment.

**Capabilities:**

- Detect supported page or target image.
- Place 2D or 3D character on page.
- Trigger animation based on story segment.
- Tap character to hear a line.
- Tap object to trigger sound effect.
- Simple mini-interaction such as feeding an animal, choosing a color, finding an object.

**MVP AR scope:**

- 2D animated characters first.
- 1 hero AR moment per story.
- 1–2 interactive objects per AR scene.
- Use image target tracking for printed pages.

**Later AR scope:**

- 3D characters.
- Multi-character scenes.
- Spatial room placement.
- Multi-user classroom AR.

### 7.1.5 Interactive Questions

**Description:**  
Guided prompts that help children understand the story.

**Question types:**

- Multiple choice with images.
- Tap the object.
- Choose the emotion.
- Repeat a word.
- Drag item to character.
- “What happens next?” with two safe choices.

**MVP requirement:**

- 3 questions per story.
- No free-form chatbot.
- Optional voice answer capture only if parent enables it.

### 7.1.6 Bedtime Mode

**Description:**  
A calmer reading mode designed for evening use.

**Capabilities:**

- Slower narration speed.
- Reduced animations.
- Darker UI.
- Lower sound effects.
- No achievement popups.
- No autoplay after story ends.
- Optional sleep timer.

**MVP priority:** High

### 7.1.7 Offline Mode

**Description:**  
Parents can download stories for offline reading.

**Capabilities:**

- Download story audio.
- Download AR assets.
- Download page metadata.
- Cache last 3–5 stories automatically.
- Parent can delete downloads.

**MVP priority:** Medium

---

## 7.2 Parent Features

### 7.2.1 Parent Onboarding

**Description:**  
Set up the child profile and safety preferences.

**Capabilities:**

- Create child profile with nickname, age range, language preference.
- Choose content level.
- Choose narration language.
- Set reading time limit.
- Enable or disable microphone.
- Enable or disable AR camera access.

**Data minimization:**

- Do not require full child name.
- Do not require birthdate; age band is enough for MVP.
- Do not require child photo.

### 7.2.2 Parent Dashboard

**Description:**  
A private dashboard showing reading activity and learning progress.

**Capabilities:**

- Stories completed.
- Total reading time.
- Favorite stories.
- Vocabulary words introduced.
- Question accuracy.
- Suggested next stories.

**MVP requirement:**

- Reading history.
- Time spent.
- Completed stories.
- Basic recommendations.

### 7.2.3 Parental Gate

**Description:**  
A gate that prevents children from accessing settings, payments, external links, or account management.

**Capabilities:**

- Simple adult verification action.
- Lock payment, settings, and privacy screens.
- Require parent approval for microphone access.
- Require parent approval for camera/AR access.

**MVP priority:** High

### 7.2.4 Reading Settings

**Capabilities:**

- Voice speed.
- Voice style.
- Language.
- Sound effects volume.
- Background music volume.
- Bedtime mode default.
- AR on/off.
- Microphone on/off.

---

## 7.3 Publisher / Admin Features

### 7.3.1 Content Studio

**Description:**  
Internal or publisher-facing tool for turning a book into an interactive experience.

**Capabilities:**

- Upload book manuscript.
- Upload page images.
- Define page order.
- Segment text by narrator and character.
- Assign voices.
- Generate audio preview.
- Upload AR assets.
- Map AR scenes to pages.
- Add interaction prompts.
- Run safety review.
- Publish to staging and production.

**MVP implementation:**

- Internal admin tool only.
- Manual upload and review.
- No self-serve publisher portal at launch.

### 7.3.2 Rights Management

**Capabilities:**

- Track content owner.
- Track territory rights.
- Track language rights.
- Track audio rights.
- Track AR/digital adaptation rights.
- Track license expiry.
- Disable expired content.

**MVP priority:** Medium, but rights metadata should exist from the beginning.

### 7.3.3 Activation Codes

**Description:**  
Support book-specific unlock codes or QR codes printed inside physical books.

**Capabilities:**

- Generate campaign codes.
- Single-use or multi-use code types.
- Expiry date.
- Publisher reporting.
- Fraud detection.

**MVP priority:** Medium

---

## 8. MVP Scope

### 8.1 MVP Goal

Launch a controlled demo that proves children and parents love the experience, while validating technical feasibility for voice narration, page recognition, and AR.

### 8.2 MVP Content

- 5 original or licensed stories.
- 5–8 pages per story.
- 1 narrator voice and 2–3 character voices per story.
- 1 AR hero scene per story.
- 3 interactive questions per story.
- Parent onboarding and basic dashboard.
- Bedtime mode.

### 8.3 MVP Must-Have Features

| Area | Must-Have |
|---|---|
| Story library | Browse and open stories |
| Audio | Pre-generated narration with character voices |
| AR | Page or image target recognition for selected scenes |
| Interaction | Tap-based questions |
| Parent control | Child profile, settings, parental gate |
| Safety | No open chat, no user-generated public content |
| Admin | Manual content upload and review |
| Analytics | Story start, completion, scan success, question answer |

### 8.4 MVP Non-Goals

The MVP should not include:

- Upload any random copyrighted book.
- Open-ended AI chatbot for children.
- Social sharing between children.
- User-generated public story marketplace.
- Real-time voice cloning.
- Complex 3D game mechanics.
- Personalized ads.
- Infinite recommendation feed.

---

## 9. Technical Architecture

## 9.1 High-Level Architecture

```text
Mobile App
  ├── Child Story Player
  ├── AR Module
  ├── Audio Playback Engine
  ├── Offline Cache
  └── Parent Dashboard

Backend API
  ├── Auth & Account Service
  ├── Child Profile Service
  ├── Story Content Service
  ├── Audio Asset Service
  ├── AR Asset Service
  ├── Story Session Service
  ├── Entitlement / Activation Code Service
  ├── Analytics Event Service
  └── Admin / Publisher Service

Async Workers
  ├── Voice Generation Worker
  ├── Audio Processing Worker
  ├── AR Asset Processing Worker
  ├── Image Target Processing Worker
  ├── Safety Review Worker
  └── Recommendation Worker

Data Layer
  ├── PostgreSQL
  ├── Redis / Key-Value Cache
  ├── Object Storage
  ├── CDN
  └── Analytics Warehouse
```

## 9.2 Recommended Client Stack

### Option A: Flutter + Unity AR Module

**Best for:** fast cross-platform development with richer AR possibilities.

| Layer | Technology |
|---|---|
| Main app | Flutter |
| AR | Unity + AR Foundation |
| Audio | Native audio plugin or Flutter audio engine |
| Offline cache | SQLite / Drift / Hive |
| Analytics | Firebase Analytics, PostHog, or custom events |

**Pros:**

- One main codebase.
- Good UI development speed.
- Unity is strong for animation and AR content.
- AR Foundation can target both ARKit and ARCore.

**Cons:**

- Unity inside Flutter increases app size.
- More complex build pipeline.
- Requires Unity expertise.

### Option B: React Native + Native AR Modules

**Best for:** startup teams with strong JavaScript/TypeScript experience.

| Layer | Technology |
|---|---|
| Main app | React Native |
| iOS AR | ARKit native module |
| Android AR | ARCore native module |
| Audio | React Native Track Player or native audio |
| Offline cache | SQLite / MMKV |

**Pros:**

- Good for app iteration.
- Strong ecosystem.
- Easier web/admin code sharing with TypeScript.

**Cons:**

- AR bridge can become complex.
- Performance tuning may require native work.

### Option C: Fully Native iOS + Android

**Best for:** premium AR quality and long-term performance.

| Layer | Technology |
|---|---|
| iOS | Swift + ARKit |
| Android | Kotlin + ARCore |
| Shared backend | TypeScript/Go/Python |

**Pros:**

- Best performance and platform control.
- Strong AR integration.
- Better camera/audio lifecycle management.

**Cons:**

- Slower and more expensive to build.
- Two app teams or strong native engineers required.

### CTO Recommendation

For the first 6 months, use:

> **Flutter or React Native for the app + Unity/AR Foundation or native AR for AR scenes.**

If the founding team is strong in TypeScript, choose React Native. If the team wants a polished child-friendly UI quickly, choose Flutter. If AR becomes the core differentiator, move more AR logic into Unity or native modules.

---

## 9.3 AR Technical Design

### 9.3.1 AR Recognition Approach

For supported books, use **reference image recognition** rather than OCR as the primary page detection method.

**Why:**

- Faster and more reliable for illustrated pages.
- Works even when text is small or stylized.
- Allows direct mapping from page image to AR scene.
- Avoids text extraction errors.

**Pipeline:**

```text
Book page image
  → Image quality validation
  → Reference image database generation
  → App downloads image target metadata
  → Camera detects target page
  → App loads AR scene mapped to page ID
```

### 9.3.2 ARKit / ARCore Capability Notes

- Apple ARKit supports detecting reference images in an AR experience and placing visual content when a known image is detected.
- Google ARCore Augmented Images supports detecting and augmenting 2D images such as posters, packaging, and printed images.
- ARCore documentation describes practical database and tracking constraints, including reference image databases and simultaneous image tracking limits. Treat those as platform constraints that should be verified during implementation.

### 9.3.3 AR Scene Model

Each AR scene should be represented as structured data:

```json
{
  "scene_id": "scene_bunny_page_03",
  "story_id": "story_bunny_forest",
  "page_id": "page_03",
  "anchor_type": "image_target",
  "assets": [
    {
      "asset_id": "bunny_2d_rig_v1",
      "type": "2d_character",
      "position": { "x": 0.1, "y": 0.0, "z": 0.0 },
      "scale": 1.0,
      "default_animation": "idle_wave"
    }
  ],
  "interactions": [
    {
      "trigger": "tap",
      "target_asset_id": "bunny_2d_rig_v1",
      "action": "play_audio_segment",
      "audio_segment_id": "bunny_line_03"
    }
  ]
}
```

### 9.3.4 AR Asset Strategy

Start with 2D animated assets, not 3D.

**Recommended MVP asset format:**

- Layered 2D characters.
- Spine, Lottie, Rive, or Unity 2D rig animation.
- Simple animations: idle, blink, wave, jump, talk, sleep.
- Transparent PNG/WebP or vector animation where appropriate.

**Why 2D first:**

- Cheaper to produce.
- Fits children's book illustration style.
- Easier to match publisher art.
- Lower device performance requirements.

Move to 3D only when a specific story requires it or when AR becomes a premium feature.

---

## 9.4 Voice and Audio Technical Design

### 9.4.1 Voice Generation Pipeline

```text
Story manuscript
  → Text cleaning
  → Page segmentation
  → Character detection / manual assignment
  → Narration script
  → Voice style assignment
  → TTS generation
  → Audio normalization
  → Sound effect mixing
  → Human review
  → Publish audio assets
```

### 9.4.2 Narration Script Format

Use a structured script format so the same story can generate audio, subtitles, highlights, and interactions.

```json
{
  "story_id": "story_bunny_forest",
  "page_id": "page_03",
  "segments": [
    {
      "segment_id": "seg_001",
      "speaker": "narrator",
      "text": "Bunny walked slowly into the quiet forest.",
      "voice_id": "narrator_warm_en_v1",
      "emotion": "curious",
      "speed": 0.92,
      "start_ms": 0,
      "end_ms": 4300
    },
    {
      "segment_id": "seg_002",
      "speaker": "bunny",
      "text": "Hello? Is anyone there?",
      "voice_id": "bunny_childlike_en_v1",
      "emotion": "gentle",
      "speed": 1.0,
      "start_ms": 4500,
      "end_ms": 6200
    }
  ]
}
```

### 9.4.3 Audio Playback Requirements

- Gapless segment playback.
- Resume from last page.
- Preload next page audio.
- Volume normalization across stories.
- Separate channels for narration, music, and sound effects.
- Bedtime audio profile.
- Offline playback.

### 9.4.4 Voice Safety Requirements

The app should avoid:

- Celebrity voice imitation.
- Cloning a parent or child voice in the MVP.
- Generating emotionally manipulative messages.
- Generating unsupervised story content for children.
- Letting children directly prompt the AI voice engine.

All generated narration should be reviewed before publication.

---

## 9.5 Backend Services

### 9.5.1 Auth Service

**Responsibilities:**

- Parent account login.
- Session management.
- Device management.
- Parental gate state.

**Recommendation:**

- Use passwordless login or OAuth for parents.
- Do not create independent child login for MVP.

### 9.5.2 Child Profile Service

**Responsibilities:**

- Store age band, language, settings.
- Store reading preferences.
- Store parent-controlled permissions.

**Data minimization:**

- Use nickname, not legal name.
- Use age band, not exact birthdate.
- Avoid child photo.

### 9.5.3 Story Content Service

**Responsibilities:**

- Story metadata.
- Page metadata.
- Narration scripts.
- Content availability.
- Age range.
- Localization.

### 9.5.4 Audio Asset Service

**Responsibilities:**

- Store generated audio URLs.
- Manage audio versions.
- Serve signed URLs.
- Handle cache invalidation.
- Track audio review status.

### 9.5.5 AR Asset Service

**Responsibilities:**

- Store AR scene metadata.
- Store AR assets.
- Map page IDs to AR scenes.
- Manage asset bundle versions.
- Serve device-compatible assets.

### 9.5.6 Story Session Service

**Responsibilities:**

- Track story start and completion.
- Track current page.
- Track interactions.
- Track question answers.
- Support resume state.

### 9.5.7 Entitlement Service

**Responsibilities:**

- Subscription access.
- Activation code unlock.
- School license access.
- Publisher campaign access.

### 9.5.8 Admin / Publisher Service

**Responsibilities:**

- Content upload.
- Review workflow.
- Rights metadata.
- Publishing workflow.
- Analytics reporting.

---

## 10. Data Model

### 10.1 Core Entities

#### `users`

Parent account.

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email TEXT UNIQUE,
  auth_provider TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

#### `child_profiles`

```sql
CREATE TABLE child_profiles (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  nickname TEXT,
  age_band TEXT CHECK (age_band IN ('3-4', '5-6', '7-8')),
  language_code TEXT NOT NULL DEFAULT 'en',
  bedtime_mode_default BOOLEAN NOT NULL DEFAULT false,
  microphone_enabled BOOLEAN NOT NULL DEFAULT false,
  ar_enabled BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

#### `stories`

```sql
CREATE TABLE stories (
  id UUID PRIMARY KEY,
  title TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  description TEXT,
  age_min INT,
  age_max INT,
  language_code TEXT NOT NULL,
  duration_seconds INT,
  cover_asset_id UUID,
  content_status TEXT CHECK (content_status IN ('draft', 'review', 'published', 'archived')),
  rights_owner_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

#### `story_pages`

```sql
CREATE TABLE story_pages (
  id UUID PRIMARY KEY,
  story_id UUID REFERENCES stories(id),
  page_number INT NOT NULL,
  page_text TEXT,
  page_image_asset_id UUID,
  image_target_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

#### `narration_segments`

```sql
CREATE TABLE narration_segments (
  id UUID PRIMARY KEY,
  story_id UUID REFERENCES stories(id),
  page_id UUID REFERENCES story_pages(id),
  speaker_key TEXT NOT NULL,
  text TEXT NOT NULL,
  voice_id TEXT NOT NULL,
  emotion TEXT,
  speed NUMERIC(4,2),
  audio_asset_id UUID,
  start_ms INT,
  end_ms INT,
  sort_order INT NOT NULL
);
```

#### `ar_scenes`

```sql
CREATE TABLE ar_scenes (
  id UUID PRIMARY KEY,
  story_id UUID REFERENCES stories(id),
  page_id UUID REFERENCES story_pages(id),
  scene_json JSONB NOT NULL,
  status TEXT CHECK (status IN ('draft', 'review', 'published', 'archived')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

#### `story_sessions`

```sql
CREATE TABLE story_sessions (
  id UUID PRIMARY KEY,
  child_profile_id UUID REFERENCES child_profiles(id),
  story_id UUID REFERENCES stories(id),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  last_page_number INT,
  mode TEXT CHECK (mode IN ('library', 'scan', 'bedtime', 'classroom'))
);
```

#### `interaction_events`

```sql
CREATE TABLE interaction_events (
  id UUID PRIMARY KEY,
  story_session_id UUID REFERENCES story_sessions(id),
  event_type TEXT NOT NULL,
  page_id UUID,
  payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

---

## 11. API Design

### 11.1 Story Library

```http
GET /v1/stories?age_band=3-4&language=en
```

Returns available stories for a child profile.

```json
{
  "stories": [
    {
      "id": "story_123",
      "title": "Bunny and the Moon",
      "age_range": "3-5",
      "duration_seconds": 420,
      "cover_url": "https://cdn.example.com/covers/bunny.png",
      "is_downloaded": false,
      "is_unlocked": true
    }
  ]
}
```

### 11.2 Story Detail

```http
GET /v1/stories/{story_id}
```

Returns metadata, pages, narration, and asset manifest.

### 11.3 Start Session

```http
POST /v1/story-sessions
```

```json
{
  "child_profile_id": "child_123",
  "story_id": "story_123",
  "mode": "bedtime"
}
```

### 11.4 Track Event

```http
POST /v1/story-sessions/{session_id}/events
```

```json
{
  "event_type": "question_answered",
  "page_id": "page_03",
  "payload": {
    "question_id": "q_001",
    "answer_id": "a_blue",
    "is_correct": true
  }
}
```

### 11.5 Page Recognition

For MVP, page recognition should mostly happen on-device through downloaded reference image metadata. A server endpoint can support fallback or content updates.

```http
GET /v1/stories/{story_id}/image-target-manifest
```

### 11.6 Activation Code

```http
POST /v1/activation-codes/redeem
```

```json
{
  "code": "BOOKY-ABCD-1234"
}
```

---

## 12. Content Production Pipeline

## 12.1 Content Workflow

```text
Acquire rights / create story
  → Upload manuscript and pages
  → Segment story by page
  → Assign speakers and voices
  → Generate narration draft
  → Add sound effects and music
  → Create AR hero moment
  → Add questions
  → Safety and editorial review
  → Device QA
  → Publish
```

## 12.2 Human Review Checklist

Every story must be reviewed for:

- Age appropriateness.
- Language simplicity.
- Cultural sensitivity.
- Emotional tone.
- Scary or intense scenes.
- Voice quality.
- Audio pronunciation.
- AR animation behavior.
- Question quality.
- Rights metadata.
- Privacy impact.

## 12.3 Story Quality Standard

A high-quality story should have:

- Clear beginning, middle, and end.
- One primary lesson or emotional arc.
- Short page text.
- Repetition for younger children.
- Strong visual anchors for AR.
- 1–2 memorable character moments.
- Calm ending for bedtime compatibility.

---

## 13. AI System Design

## 13.1 AI Use Cases

AI should assist production, not directly interact with children without guardrails.

Recommended AI use cases:

1. Draft narration script.
2. Suggest character voices.
3. Suggest comprehension questions.
4. Generate story summaries for parents.
5. Generate localization drafts.
6. Generate AR scene ideas for internal review.
7. Assist pronunciation review.

Avoid in MVP:

1. Free-form child chatbot.
2. Child-directed generative story continuation.
3. Unreviewed generated audio.
4. Real-time emotional persuasion.
5. Voice cloning.

## 13.2 AI Safety Architecture

```text
AI draft generation
  → Policy filters
  → Age appropriateness classifier
  → Human editorial review
  → Locked production assets
  → Child app only consumes approved assets
```

The child-facing app should consume approved content assets. It should not generate arbitrary story content live for the child.

## 13.3 Prompting Standards

Internal AI prompts should include:

- Target age.
- Reading level.
- Emotional tone.
- Forbidden content.
- Maximum sentence length.
- Vocabulary constraints.
- Cultural constraints.
- Output schema.

Example internal prompt structure:

```text
You are adapting a children's story for ages 4-6.
Create 3 comprehension questions.
Rules:
- No scary or violent phrasing.
- Use simple vocabulary.
- Each question must have 2-3 visual answer choices.
- Output JSON only.
```

---

## 14. Privacy, Safety, and Compliance

This product targets children, so privacy and safety are core product requirements, not legal afterthoughts.

### 14.1 Privacy Principles

- Do not collect data that is not required.
- Do not sell child data.
- Do not use targeted advertising for children.
- Do not create public child profiles.
- Do not expose child activity publicly.
- Do not require exact birthdate if age band is enough.
- Do not require microphone unless a feature needs it.
- Do not store raw child voice by default.
- Do not store camera frames by default.

### 14.2 Parent Consent

The app should implement explicit parent consent for:

- Account creation.
- Child profile creation.
- Camera / AR usage.
- Microphone usage.
- Data storage.
- Analytics beyond strictly necessary operations.
- School account usage where applicable.

### 14.3 Child Data Model

Recommended MVP child data:

| Data | Required? | Notes |
|---|---:|---|
| Nickname | Optional | Can be local-only |
| Age band | Yes | Avoid exact birthday |
| Language | Yes | Needed for content |
| Reading history | Yes | Needed for progress |
| Question answers | Optional | Parent-controlled |
| Voice recordings | No | Avoid for MVP |
| Camera frames | No | Process on-device |
| Location | No | Avoid |

### 14.4 Regulatory Awareness

The product team should consult legal counsel before launch in each market. Areas to review include:

- United States: COPPA for online services directed to children under 13.
- European Union: GDPR child consent and data protection requirements.
- United Kingdom: Age Appropriate Design Code if serving UK children.
- Vietnam: personal data protection requirements, including rules for processing children's personal data.
- Schools: additional rules may apply if the product is used in educational institutions.

### 14.5 Safety-by-Design Requirements

- No public comments.
- No direct messaging.
- No child-to-child chat.
- No open web browser.
- No external links in child mode.
- No personalized ads.
- No manipulative streak mechanics.
- No dark patterns around purchases.
- No infinite autoplay.
- No scary AR surprises by default.

---

## 15. Security Requirements

### 15.1 Account Security

- Parent-only account authentication.
- Secure session tokens.
- Device-level logout.
- Rate limiting on auth endpoints.
- Multi-factor authentication optional for parent accounts.

### 15.2 API Security

- TLS everywhere.
- JWT or session-based authentication.
- Role-based access control.
- Signed URLs for private assets.
- Request validation.
- Audit logs for admin actions.

### 15.3 Data Security

- Encrypt sensitive data at rest.
- Encrypt backups.
- Minimize logs containing personal data.
- Apply retention policy.
- Separate production and staging data.
- Regular access review.

### 15.4 Admin Security

- Admin MFA.
- Least-privilege access.
- Content publishing audit trail.
- Role separation: editor, reviewer, publisher admin, system admin.
- Manual approval required before publishing child-facing content.

---

## 16. Analytics and Metrics

### 16.1 Product Metrics

| Metric | Why It Matters |
|---|---|
| Story start rate | Measures content appeal |
| Story completion rate | Measures engagement and pacing |
| Repeat story rate | Measures child love |
| Parent return rate | Measures household habit |
| Scan success rate | Measures AR/page recognition quality |
| AR interaction rate | Measures AR usefulness |
| Bedtime mode usage | Measures parent utility |
| Activation code redemption | Measures publisher channel |

### 16.2 Learning Metrics

- Questions answered.
- Question accuracy.
- Vocabulary exposure.
- Story comprehension completion.
- Repeated vocabulary recall if future feature exists.

### 16.3 Technical Metrics

- App crash-free sessions.
- App launch time.
- Audio start latency.
- Audio buffering rate.
- AR detection latency.
- AR session FPS.
- Asset download success rate.
- API p95 latency.

### 16.4 Privacy-Preserving Analytics

Use aggregated analytics where possible. Avoid detailed behavioral profiling of individual children. Provide parents with clear controls and transparency.

---

## 17. Performance Targets

These are internal product targets and should be validated during development.

| Area | Target |
|---|---:|
| App cold start | < 3 seconds on mid-range device |
| Story audio starts | < 1 second after tapping play if cached |
| AR page detection | < 2 seconds under normal lighting |
| Story page transition | < 500 ms |
| Crash-free sessions | > 99.5% |
| Audio buffering | < 1% of sessions |
| Offline story open | < 1 second |
| Admin audio generation preview | < 2 minutes for short story draft |

---

## 18. Infrastructure Recommendation

### 18.1 MVP Infrastructure

| Component | Recommendation |
|---|---|
| Backend API | Node.js/TypeScript or Python FastAPI |
| Database | PostgreSQL |
| Cache | Redis |
| Object storage | S3-compatible storage |
| CDN | Cloudflare or cloud provider CDN |
| Queue | BullMQ, SQS, Cloud Tasks, or similar |
| Workers | Containerized async workers |
| Auth | Managed auth or custom parent auth |
| Analytics | PostHog, Firebase, or warehouse-backed events |
| Observability | OpenTelemetry + logs + error tracking |

### 18.2 Production Scaling

For production:

- Use CDN aggressively for audio and AR assets.
- Pre-generate and cache narration.
- Avoid real-time TTS for child sessions.
- Keep AR assets lightweight.
- Use background workers for asset processing.
- Separate content publishing from app-serving APIs.
- Use feature flags for content rollout.

### 18.3 Deployment Environments

- Local development.
- Staging.
- Content review environment.
- Production.

Content should never go directly from draft to production without review.

---

## 19. Admin Workflow and Roles

### 19.1 Roles

| Role | Permissions |
|---|---|
| Content Editor | Upload stories, edit scripts |
| Audio Producer | Generate and review voice assets |
| AR Designer | Upload AR scenes and animations |
| Safety Reviewer | Approve child-facing content |
| Publisher Admin | View publisher-owned content and reports |
| System Admin | Manage users, roles, infrastructure settings |

### 19.2 Publishing States

```text
Draft → Internal Review → Safety Review → Device QA → Published → Archived
```

### 19.3 Audit Requirements

Track:

- Who uploaded content.
- Who generated audio.
- Who approved safety.
- Who published.
- Which version is live.
- Which rights are attached.

---

## 20. Roadmap

## 20.1 Phase 0: Prototype — 2 to 4 Weeks

Goal: prove the magic moment.

Deliverables:

- 1 demo story.
- 3–5 pages.
- Pre-generated narration.
- 1 AR character.
- 1 page scan target.
- Simple tap interaction.
- Demo video.

Success criteria:

- A child can understand and enjoy the demo.
- A parent immediately understands the value.
- AR detection works reliably enough for demo conditions.

## 20.2 Phase 1: MVP — 8 to 12 Weeks

Deliverables:

- 5 stories.
- Parent onboarding.
- Story library.
- Story player.
- Character voices.
- 5 AR hero scenes.
- Basic parent dashboard.
- Internal content studio.
- Analytics events.

Success criteria:

- 50–100 parent beta users.
- >60% story completion rate.
- >30% repeat story rate within 7 days.
- Scan success rate >85% in controlled supported pages.

## 20.3 Phase 2: Private Beta — 3 to 6 Months

Deliverables:

- 20–30 stories.
- Improved AR interactions.
- Activation code support.
- Publisher pilot.
- School pilot.
- Offline mode.
- Localization pipeline.

Success criteria:

- 3 publisher conversations.
- 1–2 publisher pilots.
- 2–5 school pilots.
- Retention and willingness-to-pay signal.

## 20.4 Phase 3: Commercial Launch — 6 to 12 Months

Deliverables:

- Subscription or activation-code business model.
- Publisher dashboard.
- More content partnerships.
- Multiple language support.
- Better recommendation engine.
- Classroom mode.

Success criteria:

- Paid users or paid publisher contracts.
- Repeat usage habit.
- Clear content production cost model.
- Stable safety and compliance process.

---

## 21. Monetization Strategy

### 21.1 B2C Subscription

Parents pay monthly for access to premium stories.

**Pros:**

- Recurring revenue.
- Simple user model.

**Cons:**

- Requires strong content library.
- Consumer subscription acquisition can be expensive.

### 21.2 Book Activation Code

Physical books include QR or activation code to unlock audio and AR.

**Pros:**

- Strong publisher fit.
- Supports printed book sales.
- Easier parent trust if tied to known publisher.

**Cons:**

- Requires publisher partnerships.
- Operational complexity.

### 21.3 School License

Schools pay per classroom, student, or campus.

**Pros:**

- Higher contract value.
- Educational positioning.

**Cons:**

- Longer sales cycle.
- More compliance and support requirements.

### 21.4 Publisher SaaS / Platform Fee

Publishers pay to convert books into interactive audio + AR editions.

**Pros:**

- B2B revenue.
- Strong strategic moat through content supply.

**Cons:**

- Requires robust content tooling.
- Requires professional services early.

### CTO/CEO Recommendation

Start with:

1. Original/licensed demo content.
2. Publisher pilot with activation code.
3. Small paid parent beta only after content quality is validated.

Do not depend only on consumer app-store subscription in the beginning.

---

## 22. Go-To-Market Plan

### 22.1 Initial Wedge

Build a magical demo around one physical children's book.

The demo should show:

- Parent scanning a page.
- Character appearing in AR.
- Character speaking with voice.
- Child tapping character.
- Parent seeing learning summary.

### 22.2 First Customers

Prioritize:

1. Independent children's authors.
2. Small publishers.
3. Preschools and language centers.
4. Parent communities.
5. Book fairs and education events.

### 22.3 Sales Message by Segment

**Parents:**

> “Make reading time magical without turning your child into a passive screen viewer.”

**Schools:**

> “Interactive reading sessions that improve engagement and comprehension.”

**Publishers:**

> “Add a premium digital layer to your printed books and increase their shelf value.”

---

## 23. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Copyright issues | High | Use licensed/original/public-domain content first |
| Child privacy compliance | High | Privacy-by-design, parental consent, data minimization |
| AR is unstable on devices | Medium | Start with simple image targets and supported devices |
| Content production is expensive | High | 2D assets first, reusable templates, internal studio pipeline |
| App becomes too stimulating | Medium | Bedtime mode, calm design, no infinite feed |
| Parents distrust AI for kids | High | Human-reviewed content, transparent controls, no open chat |
| Publisher sales cycle is slow | Medium | Start with small authors and pilot packs |
| TTS quality is not emotional enough | Medium | Pre-generate, review, mix sound design, use curated voices |
| App size becomes large | Medium | Asset streaming, optional downloads, lightweight AR |
| Children use app without parent controls | High | Parental gate and restricted child mode |

---

## 24. Team Requirements

### 24.1 Prototype Team

- 1 mobile engineer.
- 1 AR engineer or Unity developer.
- 1 backend/full-stack engineer.
- 1 illustrator/motion designer.
- 1 content/story editor.
- 1 product/UX owner.

### 24.2 MVP Team

- Product lead.
- Mobile engineer.
- Backend engineer.
- AR/Unity engineer.
- Designer.
- Content producer.
- Child-safety/editorial reviewer.
- QA tester.

### 24.3 Later Team

- Publisher partnerships lead.
- Education specialist.
- Compliance/privacy consultant.
- Audio producer.
- Localization manager.
- Data/analytics engineer.

---

## 25. Build vs Buy Decisions

| Area | MVP Decision | Reason |
|---|---|---|
| TTS engine | Buy/API | Faster, better quality |
| Voice review tooling | Build simple internal | Need workflow control |
| AR engine | Use platform/Unity | Avoid custom AR engine |
| Story admin | Build | Core workflow and IP management |
| Auth | Buy/managed | Faster and safer |
| Analytics | Buy first | Avoid early data infra overhead |
| Content recommendation | Simple rules | ML not needed early |
| OCR | Optional buy/API | Reference image recognition is primary |

---

## 26. Product Design Guidelines

### 26.1 Child Mode

- Use big icons.
- Use voice instructions.
- Minimize text.
- Use warm colors.
- Avoid clutter.
- Avoid dark patterns.
- No external navigation.
- No purchases.

### 26.2 Parent Mode

- Clear settings.
- Privacy explanation.
- Reading summaries.
- Download management.
- Subscription/activation code area.
- Safety controls.

### 26.3 AR Design

- Keep AR moments short.
- Use AR to explain the story.
- Do not surprise children with sudden loud animation.
- Let parents disable AR.
- Make AR optional, not required for story completion.

### 26.4 Audio Design

- Voices should be clear and warm.
- Avoid overly synthetic or uncanny voices.
- Keep background music lower than narration.
- Use sound effects sparingly.
- Provide bedtime audio profile.

---

## 27. QA and Testing Plan

### 27.1 Functional Testing

- Story playback.
- Page navigation.
- Audio sync.
- Offline mode.
- AR target detection.
- Parent settings.
- Activation code redemption.
- Content publishing workflow.

### 27.2 Device Testing

Test at minimum:

- Recent iPhone.
- Older iPhone still supported by target market.
- Recent Android device.
- Mid-range Android device.
- Tablet device.

### 27.3 Child UX Testing

Observe:

- Can child start story with parent help?
- Does child understand tap interactions?
- Does AR distract from reading or support it?
- Does child want to repeat the story?
- Does parent feel the app is safe?

### 27.4 Safety Testing

- Verify no external links in child mode.
- Verify parental gate.
- Verify microphone disabled by default.
- Verify camera frames are not uploaded by default.
- Verify no unreviewed generated content appears in child app.

---

## 28. Suggested First Prototype

### Story

A simple original story: **“Bunny and the Moon”**

### Pages

5 pages:

1. Bunny sees the moon.
2. Bunny walks into the forest.
3. Bunny meets Owl.
4. Owl helps Bunny understand the moon.
5. Bunny goes home happy.

### Voice

- Narrator: warm and calm.
- Bunny: curious and bright.
- Owl: wise and gentle.

### AR Moment

Page 3: Owl appears above the book page, blinks, flaps wings, and says: “Look up, Bunny. The moon is always there.”

### Interaction

Question: “Who helped Bunny?”

Choices:

- Owl.
- Fish.
- Car.

### Demo Goal

The demo should create one immediate reaction:

> “Wow, the book came alive.”

---

## 29. Key Open Questions

1. Which market launches first: Vietnam, English-speaking global, or bilingual?
2. Is the primary channel parent app, school, or publisher partnership?
3. Will the company create original content or license existing books first?
4. Which team skill is strongest: mobile, AR, content, or partnerships?
5. How much AR quality is needed for the first paid pilot?
6. Should the brand be education-first or magic/storytelling-first?
7. Will the app support physical books only, digital books only, or both?
8. What is the acceptable cost per interactive story?
9. What legal markets must be supported at launch?
10. Should the first pilot be paid or free for feedback?

---

## 30. CEO/CTO Recommendation

The highest-probability path is:

1. Build a magical prototype with one original story and one AR moment.
2. Test it with 10–20 parents and children.
3. Measure child repeat behavior and parent trust.
4. Build 5-story MVP with parent controls and bedtime mode.
5. Approach small publishers with a book activation-code pilot.
6. Build internal content studio only after the experience proves demand.
7. Avoid open-ended AI for children until safety, trust, and compliance are mature.

The product should win by being **trusted by parents**, **loved by children**, and **useful to publishers**.

---

## 31. External Technical and Regulatory References

These references should be reviewed by the engineering and legal teams before implementation:

1. Apple Developer Documentation — Detecting Images in an AR Experience  
   https://developer.apple.com/documentation/ARKit/detecting-images-in-an-ar-experience

2. Apple Developer Documentation — ARReferenceImage  
   https://developer.apple.com/documentation/arkit/arreferenceimage

3. Google ARCore Documentation — Augmented Images  
   https://developers.google.com/ar/develop/augmented-images

4. Google ARCore Documentation — Augmented Images Developer Guide  
   https://developers.google.com/ar/develop/java/augmented-images/guide

5. FTC — Children's Online Privacy Protection Rule, COPPA  
   https://www.ftc.gov/legal-library/browse/rules/childrens-online-privacy-protection-rule-coppa

6. FTC Business Guidance — Children's Privacy  
   https://www.ftc.gov/business-guidance/privacy-security/childrens-privacy

7. GDPR Article 8 — Conditions applicable to child's consent in relation to information society services  
   https://gdpr-info.eu/art-8-gdpr/

8. Vietnam Decree 13/2023/ND-CP — Personal Data Protection reference translation  
   https://english.luatvietnam.vn/decree-no-13-2023-nd-cp-dated-april-17-2023-of-the-government-on-personal-data-protection-249791-doc1.html

---

## 32. Appendix: One-Page Pitch

**Product:** Interactive Storybook Voice + AR App

**Problem:** Children's books are valuable, but many children are more attracted to passive video content. Parents want safer, more educational screen experiences, while publishers want to increase the value of printed books.

**Solution:** A mobile app that turns children's books into narrated, interactive AR experiences. Children can scan a page, hear expressive character narration, see characters come alive, and answer simple learning prompts.

**Why Now:** AI voice generation, mobile AR, and lightweight content tooling make it possible to create magical reading experiences at much lower cost than before.

**Target Users:** Parents with children aged 3–8, schools, language centers, and children's book publishers.

**Business Model:** Book activation codes, publisher SaaS, school licenses, and optional family subscription.

**Moat:** Licensed content partnerships, content production pipeline, child-safe UX, parent trust, and proprietary library of interactive story assets.

**First MVP:** 5 original/licensed stories, character narration, 5 AR hero scenes, parent dashboard, bedtime mode, and internal content studio.
