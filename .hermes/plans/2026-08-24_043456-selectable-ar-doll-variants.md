# Selectable AR Doll Variants Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Let users choose any purchased doll variant when opening the AR story reader, instead of using the single hardcoded fox model.

**Architecture:** Add a small app-level AR character catalog in Dart, pass the selected character id/model filename through the existing `openStoryReader` method channel, and make Android/iOS load the requested bundled model. Keep the current fox as a fallback. Package all six purchased doll variants as Android `.glb` and iOS `.usdz` assets.

**Tech Stack:** Flutter/Dart, Riverpod, Android Kotlin ARCore SceneView, iOS Swift RealityKit/ARKit, glTF/GLB/USDZ assets.

---

## Current Context

- The bought Drive archive is `model-motnhi-upload.zip` (~39 MB).
- It contains six ready glTF variants:
  - `glTF_export_V01/Doll_V01.gltf`
  - `glTF_export_V02/Doll_V02.gltf`
  - `glTF_export_V03/Doll_V03.gltf`
  - `glTF_export_V04/Doll_V04.gltf`
  - `glTF_export_V05/Doll_05.gltf`
  - `glTF_export_V06/Doll_V06.gltf`
- Each variant has a `.bin` and three textures: body, eye, mouth.
- Each variant has 26 animations, including `Idle` and `HappyIdle`.
- Current code hardcodes one model:
  - Android: `scan_any_page_character.glb` in `CharacterReaderActivity.MODEL_FILENAME`
  - iOS: `scan_any_page_character.usdz` in `CharacterReaderViewController.swift`
- Current `NativeStoryReader.open()` only passes pages and `initialPageIndex`; it does not pass a character/model selection.

## Recommended Product Behavior

- Add a **Choose character** affordance before entering AR.
- User can select:
  - Existing fox/default character
  - Doll V01
  - Doll V02
  - Doll V03
  - Doll V04
  - Doll V05
  - Doll V06
- Persist the last selected character locally so the same character is preselected next time.
- AR opens with that selected model.
- If the selected asset is missing or fails to load, native code should return `model_missing` / `model_load_failed`, and Dart can show the existing AR failure UI.

## Asset Preparation

### Task 1: Choose canonical asset names

Use these stable model ids and filenames:

```text
fox_default -> scan_any_page_character.glb / scan_any_page_character.usdz
cute_doll_v01 -> cute_doll_v01.glb / cute_doll_v01.usdz
cute_doll_v02 -> cute_doll_v02.glb / cute_doll_v02.usdz
cute_doll_v03 -> cute_doll_v03.glb / cute_doll_v03.usdz
cute_doll_v04 -> cute_doll_v04.glb / cute_doll_v04.usdz
cute_doll_v05 -> cute_doll_v05.glb / cute_doll_v05.usdz
cute_doll_v06 -> cute_doll_v06.glb / cute_doll_v06.usdz
```

### Task 2: Convert glTF variants to GLB

Input paths from the bought archive:

```text
glTF_export_V01/Doll_V01.gltf
glTF_export_V02/Doll_V02.gltf
glTF_export_V03/Doll_V03.gltf
glTF_export_V04/Doll_V04.gltf
glTF_export_V05/Doll_05.gltf
glTF_export_V06/Doll_V06.gltf
```

Output Android assets:

```text
android/app/src/main/assets/cute_doll_v01.glb
android/app/src/main/assets/cute_doll_v02.glb
android/app/src/main/assets/cute_doll_v03.glb
android/app/src/main/assets/cute_doll_v04.glb
android/app/src/main/assets/cute_doll_v05.glb
android/app/src/main/assets/cute_doll_v06.glb
```

Before packaging, reorder animations so `Idle` or `HappyIdle` is animation index 0, because Android uses `ModelNode(autoAnimate = true)`.

### Task 3: Convert glTF variants to USDZ

Output iOS assets:

```text
ios/Runner/CharacterReader/cute_doll_v01.usdz
ios/Runner/CharacterReader/cute_doll_v02.usdz
ios/Runner/CharacterReader/cute_doll_v03.usdz
ios/Runner/CharacterReader/cute_doll_v04.usdz
ios/Runner/CharacterReader/cute_doll_v05.usdz
ios/Runner/CharacterReader/cute_doll_v06.usdz
```

Before packaging, make sure the first animation is `Idle` or `HappyIdle`, because iOS plays `availableAnimations.first`.

### Task 4: Add license/provenance docs

Modify:

```text
android/app/src/main/assets/ASSET_LICENSE.md
ios/Runner/CharacterReader/ASSET_LICENSE.md
```

Add a section for the purchased doll package:

```markdown
# Cute Doll Variants

- Source: purchased asset package (`model-motnhi-upload.zip`)
- Purchase price: $25
- Purchased by: [team/member/account]
- Purchase date: [fill in]
- License/source URL: [fill in from marketplace receipt]
- Distribution status: pending confirmation for App Store / Play Store redistribution
- Included variants: cute_doll_v01 ... cute_doll_v06
```

Do not ship until the marketplace license/receipt confirms redistribution rights.

---

## Code Plan

### Task 5: Add Dart AR character model

**Create:** `lib/features/ar/ar_character.dart`

```dart
import 'package:flutter/foundation.dart';

@immutable
class ArCharacter {
  const ArCharacter({
    required this.id,
    required this.displayName,
    required this.assetBaseName,
  });

  final String id;
  final String displayName;
  final String assetBaseName;
}

const arCharacters = <ArCharacter>[
  ArCharacter(
    id: 'fox_default',
    displayName: 'Fox',
    assetBaseName: 'scan_any_page_character',
  ),
  ArCharacter(id: 'cute_doll_v01', displayName: 'Doll 1', assetBaseName: 'cute_doll_v01'),
  ArCharacter(id: 'cute_doll_v02', displayName: 'Doll 2', assetBaseName: 'cute_doll_v02'),
  ArCharacter(id: 'cute_doll_v03', displayName: 'Doll 3', assetBaseName: 'cute_doll_v03'),
  ArCharacter(id: 'cute_doll_v04', displayName: 'Doll 4', assetBaseName: 'cute_doll_v04'),
  ArCharacter(id: 'cute_doll_v05', displayName: 'Doll 5', assetBaseName: 'cute_doll_v05'),
  ArCharacter(id: 'cute_doll_v06', displayName: 'Doll 6', assetBaseName: 'cute_doll_v06'),
];

ArCharacter arCharacterById(String? id) => arCharacters.firstWhere(
      (character) => character.id == id,
      orElse: () => arCharacters.first,
    );
```

### Task 6: Add Riverpod selected-character provider

**Create:** `lib/features/ar/ar_character_providers.dart`

Use `SharedPreferences` through existing DI if available. Store key:

```text
ar.selected_character_id
```

Provider should:
- default to `fox_default`
- expose current `ArCharacter`
- persist user selection
- sanitize unknown ids back to default

### Task 7: Pass selected character through Dart reader contract

**Modify:** `lib/features/ar/native_story_reader.dart`

Change interface:

```dart
Future<StoryReaderResult> open({
  required List<ArNarrationPage> pages,
  required int initialPageIndex,
  required ArCharacter character,
});
```

Add to method channel args:

```dart
'characterId': character.id,
'modelAssetBaseName': character.assetBaseName,
```

### Task 8: Pass selected character through `ArReaderController`

**Modify:** `lib/features/ar/ar_reader_controller.dart`

Add constructor field:

```dart
required this.character,
final ArCharacter character;
```

Pass to `reader.open(...)`.

### Task 9: Add UI to choose character before AR opens

**Modify:** `lib/features/player/story_player_screen.dart`

In `_openArReader()`:
1. Pause player.
2. Show a bottom sheet/grid with all `arCharacters`.
3. Save selected character.
4. Continue with existing AR preparation/opening flow.
5. If user dismisses, do not open AR.

Suggested UI title:

```text
Choose your AR friend
```

This keeps the feature scoped: selection only appears when user wants AR.

### Task 10: Android bridge parses model asset name

**Modify:** `android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/CharacterReaderBridge.kt`

Add pending field:

```kotlin
private var pendingModelAssetFileName: String = CharacterReaderActivity.MODEL_FILENAME
```

Parse argument:

```kotlin
private fun modelAssetFileName(arguments: Map<*, *>?): String {
    val baseName = arguments?.get("modelAssetBaseName") as? String
    val safeBaseName = baseName
        ?.takeIf { Regex("^[a-z0-9_]+$").matches(it) }
        ?: "scan_any_page_character"
    return "$safeBaseName.glb"
}
```

Pass to `host.launchStoryReader(...)`.

### Task 11: Android ReaderHost/Activity accepts model filename

**Modify:** likely files:

```text
android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/ReaderHost.kt
android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/CharacterReaderActivity.kt
android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/CharacterReaderScene.kt
```

Add intent extra:

```kotlin
const val EXTRA_MODEL_ASSET_FILE_NAME = "storybook_ar.character_reader.MODEL_ASSET_FILE_NAME"
```

Use it instead of hardcoded `MODEL_FILENAME`.

Validate against allowlist or strict regex:

```kotlin
Regex("^[a-z0-9_]+\\.glb$")
```

Never accept arbitrary paths.

### Task 12: iOS bridge parses model asset base name

**Modify:** `ios/Runner/CharacterReader/CharacterReaderBridge.swift`

Parse method-channel args:

```swift
let baseName = arguments?["modelAssetBaseName"] as? String
let safeBaseName = Self.safeModelAssetBaseName(baseName)
```

Use strict allowlist/regex:

```swift
private static func safeModelAssetBaseName(_ value: String?) -> String {
  guard let value,
        value.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil
  else { return "scan_any_page_character" }
  return value
}
```

Pass into `CharacterReaderViewController`.

### Task 13: iOS reader loads selected USDZ

**Modify:** `ios/Runner/CharacterReader/CharacterReaderViewController.swift`

Add property:

```swift
private let modelAssetBaseName: String
```

Replace:

```swift
Bundle.main.url(forResource: "scan_any_page_character", withExtension: "usdz")
```

with:

```swift
Bundle.main.url(forResource: modelAssetBaseName, withExtension: "usdz")
```

### Task 14: Add tests

Add/modify Dart tests:

```text
test/ar_character_test.dart
test/native_story_reader_test.dart
test/ar_reader_controller_test.dart
```

Verify:
- unknown character id defaults to fox
- selected character is passed through `NativeStoryReader.open()` args
- `ArReaderController` passes selected character to reader

Add/modify Android JVM tests if current test structure supports it:
- safe asset filename parsing rejects `../evil`
- default fallback is `scan_any_page_character.glb`

Add/modify iOS unit tests only if existing iOS test target already covers bridge logic. Otherwise validate manually on device.

---

## Verification Commands

From repo root:

```bash
flutter analyze
flutter test test/native_story_reader_test.dart test/ar_reader_controller_test.dart
```

Android asset sanity:

```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep 'cute_doll_v0[1-6]\.glb'
```

Manual device checks:

1. Open any story.
2. Tap AR.
3. Choose Doll 1.
4. Place on table; confirm Doll 1 appears and idles.
5. Close, reopen AR, choose Doll 6.
6. Confirm Doll 6 appears.
7. Confirm previous/next page reading still works.
8. Confirm selected character persists for the next AR launch.

## Risks / Open Questions

- Need purchase license/receipt details before production release.
- Need conversion tooling, probably Blender + glTF tooling for GLB and macOS/Xcode/USD tooling for USDZ.
- Need real iOS/Android device validation.
- Need to confirm final asset sizes after GLB/USDZ conversion; six animated variants may increase app bundle size.
- Need final display names: `Doll 1` ... `Doll 6` are placeholders unless design wants names.
