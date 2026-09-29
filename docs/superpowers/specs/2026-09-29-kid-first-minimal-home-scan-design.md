# Less-is-more child Home and scanning design

**Date:** 2026-09-29
**Status:** Implemented; physical-device camera review pending
**Visual reference:** [Home, scanner, and grown-up handoff](https://app.paper.design/file/01M3DXY6WQN072R1SMD0GH5Z7N/p-1-0)

## Goal

Make the child's first and most-used screens understandable before reading a paragraph. The primary action is **Scan my book**; words confirm recognizable pictures and icons instead of competing with them. This refines, but does not change, the approved two-tap speakable-page and consent boundaries.

## Home

- Show a small greeting and quiet gated Parent entry, then a large illustrated scan hero with **Scan my book** as the only strong action. Use the app's day/moon theme tokens, generous tap targets, and actual story data.
- Below the hero, show two available story covers with short titles and a **More stories** route. No theme filters or full story grid in the first viewport. The full library view retains theme filters and all stories, including empty/loading/error states.
- Keep **Home** and **My books** in the child bottom navigation. The existing Moon Mode control moves to the full library/reading settings rather than disappearing as a capability; Parent access remains available.
- If the library is unavailable or empty, the scan action still renders and the shelf gives a concise retry/empty state. The action is never masked by library loading.

## Scan journey

- Flutter checks fresh effective page-image and cloud-narration consent before opening the native camera, as it does today. Without either, show the illustrated **A grown-up can help** state: one sentence, **Ask a grown-up** through the existing parent gate to Privacy & data, and **Pick a story instead** back to Home. No image is uploaded or camera opened.
- On iOS, retain automatic document detection/capture, but use a short title, a clear live rectangle, and one localized bottom cue at a time: **Find a page**, **Move closer**, **Hold still**. Do not show a shutter. Changes in recognition/stability update the cue, and the cue stays accessible to VoiceOver. The native scanner remains cancelable.
- Android's Google document-scanner UI is system-controlled; retain its capture experience. Flutter's setup, preparing, ready, blocked, and failure states are shared across platforms.
- Preparing is a calm full-screen state with **Making your page ready…** and no Listen action. Ready keeps the approved photographed page and one prominent **Listen** button. Listening retains Pause/Resume/Replay and page highlight.
- Blocked shows only a child-safe short message and **Try another page**, without rejected image/text or Listen. Technical failure has a retry action and distinct copy. Camera permission/unavailable failures can point to grown-up help rather than promising a successful rescan.

## Boundaries and verification

- Preserve existing consent rechecks, proof-gated validation, audio cleanup, single-flight/generation guards, and native OCR geometry. Do not infer a safe page from camera capture alone.
- Localize new child-facing labels in English and Vietnamese. Give icon actions semantic labels and keep visible text on important choices.
- Widget tests cover Home's primary action and secondary library route, story selection, consent-off handoff, and blocked/failed/ready action visibility. Native iOS tests/checks cover the cue mapping; run Flutter analysis and focused tests. Validate the camera overlay on a physical iOS device when available.
