# Native AR Story Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the real ARKit/ARCore character reader read any story - curated or user-recorded - page by page in one AR session, and retire the 2D camera-preview AR path.

**Architecture:** A Dart preparation step (`ArNarrationBundle`) turns a `StoryDetail` into local audio files under `Directory.systemTemp`, one per narration segment. A new `openStoryReader` method on the existing `storybook_ar/character_reader` channel hands the native reader a page-indexed playlist; the reader places one anchor and swaps only the audio data source as the child navigates pages. On close it returns the page id it ended on. Android's character reader is promoted from debug-only to all build variants.

**Tech Stack:** Flutter 3.10 / Dart, Riverpod, `flutter_tts` 4.2.5, `just_audio`, `dio`; Kotlin + ARCore 1.54 + arsceneview 4.18 + Compose; Swift + ARKit/RealityKit.

**Spec:** `docs/superpowers/specs/2026-08-23-native-ar-story-reader-design.md`

## Global Constraints

- **Audio directory is `Directory.systemTemp`.** Never `getApplicationCacheDirectory()` - on iOS that returns `Library/Caches`, which is outside the validator root, and every path would be rejected. (Spec 3.2)
- **Device-TTS file formats are platform-fixed:** `.caf` on iOS, `.wav` on Android. iOS cannot encode MP3. (Spec 3.3)
- **Segment is the unit of preparation; page is the unit of navigation.** Curated pages carry 2-3 segments. (Spec 3.1)
- **Audio filename pattern:** `ar_<sanitizedStoryId>_p<pageNumber>_s<sortOrder>.<ext>` where `sanitizedStoryId` is the story id stripped of non-alphanumerics and truncated to 32 chars, `pageNumber` is the 1-based `StoryPage.pageNumber`, `sortOrder` is the segment's `sortOrder`, and `ext` is one of `mp3|wav|caf|m4a`. **Neither number is a list index.** (Spec 5.1.2)
- **Validator containment rule is unchanged.** Paths must still resolve under `cacheDir` (Android) / `temporaryDirectory` (iOS) after symlink resolution. Only the basename check relaxes. (Spec 6.3)
- **`openCharacterReader` is unchanged.** The scan-any-page flow must keep working identically at every step.
- **Never run `flutter run`.** Never run widget, e2e, or integration tests during implementation - unit tests only. (Project convention)
- **`flutter analyze` must be filtered by severity**, never truncated: `flutter analyze 2>&1 | grep 'error •'`, and rely on the exit code.

---

### Task 1: Promote the Android character reader to all build variants

Independent of every other task. After this, AR still only opens from scan-any-page, but it does so in release builds too.

**Files:**
- Move: `android/app/src/debug/kotlin/com/storybookar/storybook_ar/characterreader/` (9 files) -> `android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/`
- Move: `android/app/src/debug/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt` -> `android/app/src/main/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt`
- Move: `android/app/src/debug/assets/` (2 files, **untracked - use `mv`, not `git mv`**) -> `android/app/src/main/assets/`
- Move: `android/app/src/testDebug/kotlin/` (3 files) -> `android/app/src/test/kotlin/`
- Delete: `android/app/src/release/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt`
- Delete: `android/app/src/profile/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt`
- Modify: `android/app/build.gradle.kts:56-88`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/debug/AndroidManifest.xml`

**Interfaces:**
- Consumes: nothing.
- Produces: `com.storybookar.storybook_ar.characterreader.*` visible to all variants; `ScanAnyPageBridges.READER_REQUEST_CODE` available in `src/main`.

- [ ] **Step 1: Move the Kotlin sources and tests**

```bash
cd /Users/androidker/Projects/app-book/android/app/src
git mv debug/kotlin/com/storybookar/storybook_ar/characterreader main/kotlin/com/storybookar/storybook_ar/characterreader
git mv debug/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt main/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt
git mv testDebug/kotlin/com/storybookar/storybook_ar/characterreader test/kotlin/com/storybookar/storybook_ar/characterreader
git mv testDebug/kotlin/com/storybookar/storybook_ar/NativeFailureMappingTest.kt test/kotlin/com/storybookar/storybook_ar/NativeFailureMappingTest.kt
git rm release/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt
git rm profile/kotlin/com/storybookar/storybook_ar/ScanAnyPageBridges.kt
rmdir -p debug/kotlin/com/storybookar/storybook_ar testDebug/kotlin/com/storybookar/storybook_ar 2>/dev/null || true
```

- [ ] **Step 2: Move the model asset (untracked - plain `mv`)**

The model is untracked, so `git mv` fails here. `CharacterReaderActivity.modelExists()` opens it from `assets`; leaving it behind makes every release `openStoryReader` exit `model_missing`.

```bash
cd /Users/androidker/Projects/app-book/android/app/src
mkdir -p main/assets
mv debug/assets/scan_any_page_character.glb main/assets/
mv debug/assets/ASSET_LICENSE.md main/assets/
rmdir debug/assets
ls -la main/assets/
```

Expected: both files listed under `main/assets/`.

- [ ] **Step 3: Promote the dependencies**

In `android/app/build.gradle.kts`, replace the `dependencies` block body from the ARCore line through `testCompileOnly("androidx.compose.runtime:runtime")` with:

```kotlin
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("com.google.ar:core:1.54.0")
    // Pinned to 4.18.0 deliberately: this is the newest arsceneview whose
    // kotlin-stdlib constraint (2.3.21, metadata 2.3.0) the project's Kotlin
    // 2.2.20 compiler can read. 4.19.0+ strictly require kotlin-stdlib 2.4.x,
    // whose 2.4.0 metadata this compiler rejects, which fails the build.
    // Raising this version requires bumping the Kotlin plugin first.
    implementation("io.github.sceneview:arsceneview:4.18.0")
    // arsceneview already brings compose-bom, compose.ui and compose.foundation
    // transitively. This is only for ComponentActivity.setContent.
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation(platform("androidx.compose:compose-bom:2026.05.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    testImplementation("junit:junit:4.13.2")
```

Also update the stale comment at `build.gradle.kts:56-59` to:

```kotlin
    // The page scanner and the ARCore character reader both ship in release builds.
```

and the `buildFeatures.compose` comment at lines 3-8 to drop "every @Composable is debug-only".

The `compileOnly` / `testCompileOnly` Compose shims are deleted outright - they existed only to satisfy the module-wide Compose compiler while Compose itself was debug-only.

- [ ] **Step 4: Move the AR manifest entries into `src/main`**

In `android/app/src/main/AndroidManifest.xml`, add next to the existing `<uses-feature>` at line 8:

```xml
    <uses-feature android:name="android.hardware.camera.ar" android:required="false"/>
```

and inside `<application>`:

```xml
        <meta-data android:name="com.google.ar.core" android:value="optional"/>
        <activity
            android:name=".characterreader.CharacterReaderActivity"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:exported="false"
            android:hardwareAccelerated="true"
            android:theme="@android:style/Theme.Material.NoActionBar"/>
```

Then reduce `android/app/src/debug/AndroidManifest.xml` to only its development affordances - `usesCleartextTraffic` and the debug `INTERNET` permission must **not** reach release:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- The INTERNET permission is required for development. Specifically,
         the Flutter tool needs it to communicate with the running application
         to allow setting breakpoints, to provide hot reload, etc.
    -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <!-- Debug-only: allow plain HTTP so a device/emulator can reach the local
         backend (http://<mac-lan-ip>:8000). targetSdk >= 28 denies cleartext by
         default. This overlay is NOT merged into release builds, where
         resolveApiBaseUrl() already requires an HTTPS, non-loopback host. -->
    <application android:usesCleartextTraffic="true"/>
</manifest>
```

- [ ] **Step 5: Run the unit tests in the default source set**

```bash
cd /Users/androidker/Projects/app-book/android && ./gradlew :app:testDebugUnitTest
```

Expected: PASS. The three moved test classes now compile against `src/main` sources. If `CharacterReaderBridgeTest` or `AudioPathValidatorTest` fail to resolve their subjects, the Step 1 move is incomplete.

- [ ] **Step 6: Verify a release build actually assembles with R8**

```bash
cd /Users/androidker/Projects/app-book && flutter build apk --release
```

Expected: BUILD SUCCESSFUL. This is the step that catches missing ProGuard keeps for Filament/ARCore JNI. arsceneview 4.18 ships consumer rules covering this, so no manual rules are expected - if R8 strips something, add keeps rather than disabling minification.

- [ ] **Step 7: Confirm the model landed in the release APK**

```bash
cd /Users/androidker/Projects/app-book && unzip -l build/app/outputs/flutter-apk/app-release.apk | grep -i 'scan_any_page_character\|assets/ASSET_LICENSE'
```

Expected: `assets/scan_any_page_character.glb` listed. An empty result means Step 2 did not take effect and release AR will fail with `model_missing`.

- [ ] **Step 8: Commit**

```bash
cd /Users/androidker/Projects/app-book
git add android/app/src android/app/build.gradle.kts
git commit -m "build(android): ship the ARCore character reader in release builds"
```

---

### Task 2: Relax both audio path validators to a pattern allowlist

**Files:**
- Modify: `android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/AudioPathValidator.kt`
- Modify: `ios/Runner/CharacterReader/CharacterReaderBridge.swift:1-46`
- Test: `android/app/src/test/kotlin/com/storybookar/storybook_ar/characterreader/AudioPathValidatorTest.kt`
- Test: `ios/RunnerTests/CharacterReaderTests.swift`

**Interfaces:**
- Consumes: Task 1's source-set layout.
- Produces: `AudioPathValidator.validate(path: String?): File?` accepting the new pattern; `AudioPathValidator.isAllowedName(name: String): Boolean`. Swift: `CharacterReaderAudioPathValidator.validate(path:) -> URL?` with the same acceptance.

- [ ] **Step 1: Write the failing Kotlin tests**

Append to `AudioPathValidatorTest.kt` (keep every existing test - the legacy name must still work):

```kotlin
    @Test
    fun `accepts an ar segment file name`() {
        val file = File(cacheDir, "ar_abc123_p1_s0.mp3")
        file.writeBytes(byteArrayOf(1, 2, 3))
        assertNotNull(AudioPathValidator(cacheDir).validate(file.path))
    }

    @Test
    fun `accepts every allowed extension`() {
        for (ext in listOf("mp3", "wav", "caf", "m4a")) {
            val file = File(cacheDir, "ar_abc123_p2_s1.$ext")
            file.writeBytes(byteArrayOf(1))
            assertNotNull("extension $ext should be allowed",
                AudioPathValidator(cacheDir).validate(file.path))
        }
    }

    @Test
    fun `rejects a disallowed extension`() {
        val file = File(cacheDir, "ar_abc123_p1_s0.exe")
        file.writeBytes(byteArrayOf(1))
        assertNull(AudioPathValidator(cacheDir).validate(file.path))
    }

    @Test
    fun `rejects an unanchored match`() {
        val file = File(cacheDir, "evil_ar_abc123_p1_s0.mp3")
        file.writeBytes(byteArrayOf(1))
        assertNull(AudioPathValidator(cacheDir).validate(file.path))
    }

    @Test
    fun `rejects an ar name outside the cache dir`() {
        val outside = File(System.getProperty("java.io.tmpdir"), "ar_abc123_p1_s0.mp3")
        outside.writeBytes(byteArrayOf(1))
        assertNull(AudioPathValidator(cacheDir).validate(outside.path))
    }
```

- [ ] **Step 2: Run them to verify they fail**

```bash
cd /Users/androidker/Projects/app-book/android && ./gradlew :app:testDebugUnitTest --tests '*AudioPathValidatorTest*'
```

Expected: FAIL - the new-name tests fail on the `requested.name != EXPECTED_FILENAME` check.

- [ ] **Step 3: Implement the pattern allowlist**

Replace `AudioPathValidator.kt` in full:

```kotlin
package com.storybookar.storybook_ar.characterreader

import java.io.File

class AudioPathValidator(
    private val cacheDir: File,
) {
    fun validate(path: String?): File? {
        if (path.isNullOrBlank()) return null

        val requested = File(path)
        if (!requested.isAbsolute) return null
        if (!isAllowedName(requested.name)) return null

        val resolvedCache = runCatching { cacheDir.canonicalFile }.getOrNull() ?: return null
        val resolvedAudio = runCatching { requested.canonicalFile }.getOrNull() ?: return null
        // Checked again after symlink resolution: the pre-resolution name is
        // attacker-controlled and a symlink can point somewhere else entirely.
        if (!isAllowedName(resolvedAudio.name)) return null
        if (!resolvedAudio.isFile || !resolvedAudio.canRead()) return null

        var cursor: File? = resolvedAudio.parentFile
        while (cursor != null) {
            if (cursor == resolvedCache) return resolvedAudio
            cursor = cursor.parentFile
        }
        return null
    }

    companion object {
        /** The single-clip name the scan-any-page flow has always used. */
        const val EXPECTED_FILENAME = "scan_any_page_narration.mp3"

        /**
         * Per-segment clips prepared for the story reader:
         * `ar_<sanitizedStoryId>_p<pageNumber>_s<sortOrder>.<ext>`. Anchored, because an
         * unanchored match would accept `evil_ar_x_p1_s0.mp3`.
         */
        private val STORY_SEGMENT_FILENAME =
            Regex("""^ar_[A-Za-z0-9]{1,32}_p\d{1,4}_s\d{1,4}\.(mp3|wav|caf|m4a)$""")

        fun isAllowedName(name: String): Boolean =
            name == EXPECTED_FILENAME || STORY_SEGMENT_FILENAME.matches(name)
    }
}
```

- [ ] **Step 4: Run the Kotlin tests**

```bash
cd /Users/androidker/Projects/app-book/android && ./gradlew :app:testDebugUnitTest --tests '*AudioPathValidatorTest*'
```

Expected: PASS, including every pre-existing test.

- [ ] **Step 5: Apply the same change in Swift**

In `ios/Runner/CharacterReader/CharacterReaderBridge.swift`, replace the `CharacterReaderAudioPathValidator` struct's name handling. Both `lastPathComponent` checks (pre- and post-symlink-resolution) must use the new predicate:

```swift
struct CharacterReaderAudioPathValidator {
  private static let expectedFilename = "scan_any_page_narration.mp3"
  /// Per-segment clips prepared for the story reader. Anchored, because an
  /// unanchored match would accept `evil_ar_x_p1_s0.mp3`.
  private static let storySegmentFilename = try! NSRegularExpression(
    pattern: "^ar_[A-Za-z0-9]{1,32}_p[0-9]{1,4}_s[0-9]{1,4}\\.(mp3|wav|caf|m4a)$"
  )

  static func isAllowedName(_ name: String) -> Bool {
    if name == expectedFilename { return true }
    let range = NSRange(name.startIndex..<name.endIndex, in: name)
    return storySegmentFilename.firstMatch(in: name, range: range) != nil
  }

  let temporaryDirectory: URL

  func validate(path: String) -> URL? {
    guard !path.isEmpty, NSString(string: path).isAbsolutePath else { return nil }

    let resolvedTemporaryDirectory = temporaryDirectory
      .resolvingSymlinksInPath()
      .standardizedFileURL
    let requestedURL = URL(fileURLWithPath: path).standardizedFileURL
    let resolvedURL = requestedURL
      .resolvingSymlinksInPath()
      .standardizedFileURL
    let temporaryComponents = resolvedTemporaryDirectory.pathComponents
    let candidateComponents = resolvedURL.pathComponents
    guard
      Self.isAllowedName(requestedURL.lastPathComponent),
      Self.isAllowedName(resolvedURL.lastPathComponent),
      candidateComponents.count > temporaryComponents.count,
      candidateComponents.prefix(temporaryComponents.count).elementsEqual(temporaryComponents)
    else {
      return nil
    }

    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedURL.path),
      attributes[.type] as? FileAttributeType == .typeRegular,
      FileManager.default.isReadableFile(atPath: resolvedURL.path)
    else {
      return nil
    }
    return resolvedURL
  }
}
```

- [ ] **Step 6: Mirror the Kotlin cases in `CharacterReaderTests.swift`**

Add tests asserting: `ar_abc123_p1_s0.mp3` under `temporaryDirectory` validates; each of `wav`/`caf`/`m4a` validates; `.exe` is rejected; `evil_ar_abc123_p1_s0.mp3` is rejected; an `ar_`-named file outside `temporaryDirectory` is rejected.

- [ ] **Step 7: Commit**

```bash
cd /Users/androidker/Projects/app-book
git add android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/AudioPathValidator.kt \
        android/app/src/test/kotlin/com/storybookar/storybook_ar/characterreader/AudioPathValidatorTest.kt \
        ios/Runner/CharacterReader/CharacterReaderBridge.swift ios/RunnerTests/CharacterReaderTests.swift
git commit -m "feat(ar): accept per-segment story clips in both audio path validators"
```

---

### Task 3: `ArNarrationBundle` - prepare per-segment audio files

Pure Dart, no native dependency. The riskiest logic in the slice, so it gets the heaviest test coverage.

**Files:**
- Create: `lib/features/ar/ar_narration_bundle.dart`
- Test: `test/ar_narration_bundle_test.dart`

**Interfaces:**
- Consumes: `StoryDetail`, `NarrationSegment`, `AssetUrlResolver`, `NarrationAudioFetcher`.
- Produces:
  - `class ArNarrationPage { String pageId; int pageNumber; List<String> audioFilePaths; Map<String, dynamic> toJson(); }`
  - `class ArNarrationFailure implements Exception { String code; }`
  - `abstract interface class TtsFileSynthesizer { String get fileExtension; Future<bool> synthesizeToFile(String text, String filePath); }`
  - `abstract interface class ArAudioDownloader { Future<List<int>> download(String url); }`
  - `String arSegmentFileName({required String storyId, required int pageNumber, required int sortOrder, required String extension})`
  - `Future<List<ArNarrationPage>> prepareArNarration({...})`

- [ ] **Step 1: Write the failing tests**

Create `test/ar_narration_bundle_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/sources/asset_url_resolver.dart';
import 'package:storybook_ar/features/ar/ar_narration_bundle.dart';
import 'package:storybook_ar/features/player/narration_audio_fetcher.dart';

class _FakeResolver implements AssetUrlResolver {
  _FakeResolver(this.urls);
  final Map<String, String> urls;
  @override
  Future<Map<String, String>> resolve(List<String> ids) async =>
      {for (final id in ids) if (urls.containsKey(id)) id: urls[id]!};
}

class _FakeDownloader implements ArAudioDownloader {
  final downloaded = <String>[];
  @override
  Future<List<int>> download(String url) async {
    downloaded.add(url);
    return [1, 2, 3];
  }
}

class _FakeTts implements TtsFileSynthesizer {
  _FakeTts({this.succeeds = true});
  final bool succeeds;
  final synthesized = <String>[];
  @override
  String get fileExtension => 'wav';
  @override
  Future<bool> synthesizeToFile(String text, String filePath) async {
    if (!succeeds) return false;
    synthesized.add(text);
    await File(filePath).writeAsBytes([9]);
    return true;
  }
}

class _FakeFetcher implements NarrationAudioFetcher {
  _FakeFetcher(this.directory);
  final Directory directory;
  final requested = <String>[];
  @override
  Future<String?> pathFor(NarrationSegment segment) async {
    requested.add(segment.id);
    final file = File('${directory.path}/narration_${segment.id}.mp3');
    await file.writeAsBytes([7, 7]);
    return file.path;
  }

  @override
  Future<void> dispose() async {}
}

NarrationSegment _segment({
  required String id,
  required String pageId,
  required int sortOrder,
  String? assetId,
  String text = 'hello',
}) =>
    NarrationSegment(
      id: id,
      storyId: 'story-1',
      pageId: pageId,
      speakerKey: 'narrator',
      text: text,
      voiceId: 'v1',
      audioAssetId: assetId,
      sortOrder: sortOrder,
    );

StoryDetail _detail({
  required List<StoryPage> pages,
  required List<NarrationSegment> segments,
}) =>
    StoryDetail(
      // id/title/slug are the only required fields; everything else defaults.
      // `contentStatus` is a ContentStatus enum, not a String - do not pass one.
      story: const Story(id: 'story-1', title: 'T', slug: 's'),
      pages: pages,
      segments: segments,
    );

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ar_bundle_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('builds a file name that is story-scoped and uses page/sort numbers', () {
    expect(
      arSegmentFileName(
        storyId: 'ab-cd-ef',
        pageNumber: 2,
        sortOrder: 1,
        extension: 'mp3',
      ),
      'ar_abcdef_p2_s1.mp3',
    );
  });

  test('keeps every segment of a multi-segment page', () async {
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [
        _segment(id: 's1', pageId: 'p1', sortOrder: 0, assetId: 'a1'),
        _segment(id: 's2', pageId: 'p1', sortOrder: 1, assetId: 'a2'),
        _segment(id: 's3', pageId: 'p1', sortOrder: 2, assetId: 'a3'),
      ],
    );
    final pages = await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver({'a1': 'u1', 'a2': 'u2', 'a3': 'u3'}),
      fetcher: null,
      tts: _FakeTts(),
      downloader: _FakeDownloader(),
      directory: dir,
    );

    expect(pages, hasLength(1));
    expect(pages.single.audioFilePaths, hasLength(3));
    expect(
      pages.single.audioFilePaths.map((p) => p.split('/').last),
      ['ar_story1_p1_s0.mp3', 'ar_story1_p1_s1.mp3', 'ar_story1_p1_s2.mp3'],
    );
  });

  test('copies the fetcher clip instead of renaming it', () async {
    final fetcher = _FakeFetcher(dir);
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [_segment(id: 's1', pageId: 'p1', sortOrder: 0)],
    );
    await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: fetcher,
      tts: _FakeTts(),
      downloader: _FakeDownloader(),
      directory: dir,
    );

    // The fetcher's own file must survive - the player still holds this path.
    expect(File('${dir.path}/narration_s1.mp3').existsSync(), isTrue);
    expect(File('${dir.path}/ar_story1_p1_s0.mp3').existsSync(), isTrue);
  });

  test('falls back to device TTS when nothing else resolves', () async {
    final tts = _FakeTts();
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [_segment(id: 's1', pageId: 'p1', sortOrder: 0, text: 'spoken')],
    );
    final pages = await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: null,
      tts: tts,
      downloader: _FakeDownloader(),
      directory: dir,
    );

    expect(tts.synthesized, ['spoken']);
    expect(pages.single.audioFilePaths.single, endsWith('ar_story1_p1_s0.wav'));
  });

  test('synthesizes from page text when a page has no segments', () async {
    final tts = _FakeTts();
    final detail = _detail(
      pages: [
        const StoryPage(
          id: 'p1',
          storyId: 'story-1',
          pageNumber: 1,
          pageText: 'page words',
        ),
      ],
      segments: const [],
    );
    final pages = await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: null,
      tts: tts,
      downloader: _FakeDownloader(),
      directory: dir,
    );

    expect(tts.synthesized, ['page words']);
    expect(pages.single.audioFilePaths, hasLength(1));
  });

  test('fails the whole bundle when one segment cannot be prepared', () async {
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [_segment(id: 's1', pageId: 'p1', sortOrder: 0)],
    );
    expect(
      () => prepareArNarration(
        detail: detail,
        resolver: _FakeResolver(const {}),
        fetcher: null,
        tts: _FakeTts(succeeds: false),
        downloader: _FakeDownloader(),
        directory: dir,
      ),
      throwsA(isA<ArNarrationFailure>()
          .having((e) => e.code, 'code', 'narration_unavailable')),
    );
  });

  test('deletes stale files for this story before preparing', () async {
    final stale = File('${dir.path}/ar_story1_p9_s0.mp3')..writeAsBytesSync([0]);
    final other = File('${dir.path}/ar_other_p1_s0.mp3')..writeAsBytesSync([0]);
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [_segment(id: 's1', pageId: 'p1', sortOrder: 0)],
    );
    await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: null,
      tts: _FakeTts(),
      downloader: _FakeDownloader(),
      directory: dir,
    );

    expect(stale.existsSync(), isFalse, reason: 'stale clip for this story');
    expect(other.existsSync(), isTrue, reason: 'another story must be untouched');
  });

  test('reports progress once per segment', () async {
    final seen = <String>[];
    final detail = _detail(
      pages: [
        const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1),
        const StoryPage(id: 'p2', storyId: 'story-1', pageNumber: 2),
      ],
      segments: [
        _segment(id: 's1', pageId: 'p1', sortOrder: 0),
        _segment(id: 's2', pageId: 'p1', sortOrder: 1),
        _segment(id: 's3', pageId: 'p2', sortOrder: 0),
      ],
    );
    await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: null,
      tts: _FakeTts(),
      downloader: _FakeDownloader(),
      directory: dir,
      onProgress: (done, total) => seen.add('$done/$total'),
    );

    expect(seen, ['1/3', '2/3', '3/3']);
  });
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd /Users/androidker/Projects/app-book && flutter test test/ar_narration_bundle_test.dart
```

Expected: FAIL - `ar_narration_bundle.dart` does not exist.

- [ ] **Step 3: Implement the bundle**

Create `lib/features/ar/ar_narration_bundle.dart`:

```dart
import 'dart:io';

import '../../data/models/models.dart';
import '../../data/sources/asset_url_resolver.dart';
import '../player/narration_audio_fetcher.dart';

/// One page of prepared AR narration: the page's clips, in `sort_order`.
class ArNarrationPage {
  const ArNarrationPage({
    required this.pageId,
    required this.pageNumber,
    required this.audioFilePaths,
  });

  final String pageId;
  final int pageNumber;
  final List<String> audioFilePaths;

  Map<String, dynamic> toJson() => {
        'pageId': pageId,
        'pageNumber': pageNumber,
        'audioFilePaths': audioFilePaths,
      };
}

final class ArNarrationFailure implements Exception {
  const ArNarrationFailure(this.code);

  final String code;
}

/// Writes a spoken clip to an exact path. Abstracted over `flutter_tts` so the
/// bundle is testable, and so the platform-specific container format
/// ([fileExtension]) lives in exactly one place.
abstract interface class TtsFileSynthesizer {
  /// `caf` on iOS, `wav` on Android. iOS cannot encode MP3.
  String get fileExtension;

  Future<bool> synthesizeToFile(String text, String filePath);
}

/// Fetches the bytes behind a signed asset URL.
abstract interface class ArAudioDownloader {
  Future<List<int>> download(String url);
}

/// `ar_<sanitizedStoryId>_p<pageNumber>_s<sortOrder>.<ext>`.
///
/// Story-scoped because the directory outlives a single run: without the story
/// id, a failed preparation would leave the previous story's clip in place,
/// passing validation, and AR would narrate the wrong book.
String arSegmentFileName({
  required String storyId,
  required int pageNumber,
  required int sortOrder,
  required String extension,
}) {
  final stripped = storyId.replaceAll(RegExp('[^A-Za-z0-9]'), '');
  // The native validators require 1..32 characters, so an id that sanitizes to
  // nothing still has to produce a legal name.
  final safe = stripped.isEmpty ? 'x' : stripped;
  final scoped = safe.length > 32 ? safe.substring(0, 32) : safe;
  return 'ar_${scoped}_p${pageNumber}_s$sortOrder.$extension';
}

String _storyFilePrefix(String storyId) {
  final name = arSegmentFileName(
    storyId: storyId,
    pageNumber: 0,
    sortOrder: 0,
    extension: 'mp3',
  );
  return name.substring(0, name.indexOf('_p'));
}

/// Prepares one local audio file per narration segment, ready for the native
/// story reader.
///
/// Resolution order per segment: a registered clip's signed URL, then the
/// authored-story TTS fetcher, then on-device speech synthesis. Preparation is
/// all-or-nothing: a partial bundle would break the page-id mapping and risk
/// playing a stale file.
Future<List<ArNarrationPage>> prepareArNarration({
  required StoryDetail detail,
  required AssetUrlResolver resolver,
  required NarrationAudioFetcher? fetcher,
  required TtsFileSynthesizer tts,
  required ArAudioDownloader downloader,
  required Directory directory,
  void Function(int done, int total)? onProgress,
}) async {
  final storyId = detail.story.id;
  final pages = detail.orderedPages;

  await _deleteStaleClips(directory, _storyFilePrefix(storyId));

  final units = <_Unit>[];
  for (final page in pages) {
    final segments = detail.segmentsForPage(page.id);
    if (segments.isEmpty) {
      // No segment row at all: speak the page text so the page is never silent.
      units.add(_Unit(page: page, segment: null, text: page.pageText ?? ''));
      continue;
    }
    for (final segment in segments) {
      units.add(_Unit(page: page, segment: segment, text: segment.text));
    }
  }

  final assetIds = [
    for (final unit in units)
      if (unit.segment?.hasAudioAsset ?? false) unit.segment!.audioAssetId!,
  ];
  final urls = assetIds.isEmpty
      ? const <String, String>{}
      : await resolver.resolve(assetIds);

  final pathsByPageId = <String, List<String>>{};
  var done = 0;
  for (final unit in units) {
    final path = await _prepareUnit(
      unit: unit,
      storyId: storyId,
      urls: urls,
      fetcher: fetcher,
      tts: tts,
      downloader: downloader,
      directory: directory,
    );
    pathsByPageId.putIfAbsent(unit.page.id, () => <String>[]).add(path);
    onProgress?.call(++done, units.length);
  }

  return [
    for (final page in pages)
      ArNarrationPage(
        pageId: page.id,
        pageNumber: page.pageNumber,
        audioFilePaths: pathsByPageId[page.id] ?? const <String>[],
      ),
  ];
}

class _Unit {
  _Unit({required this.page, required this.segment, required this.text});

  final StoryPage page;
  final NarrationSegment? segment;
  final String text;

  int get sortOrder => segment?.sortOrder ?? 0;
}

Future<String> _prepareUnit({
  required _Unit unit,
  required String storyId,
  required Map<String, String> urls,
  required NarrationAudioFetcher? fetcher,
  required TtsFileSynthesizer tts,
  required ArAudioDownloader downloader,
  required Directory directory,
}) async {
  String target(String extension) =>
      '${directory.path}/${arSegmentFileName(
        storyId: storyId,
        pageNumber: unit.page.pageNumber,
        sortOrder: unit.sortOrder,
        extension: extension,
      )}';

  final segment = unit.segment;

  // 1. A registered clip.
  final url = segment != null && segment.hasAudioAsset
      ? urls[segment.audioAssetId]
      : null;
  if (url != null) {
    try {
      final bytes = await downloader.download(url);
      if (bytes.isNotEmpty) {
        return _writeAtomically(target('mp3'), bytes);
      }
    } catch (_) {
      // Fall through: a failed download must not lose the page.
    }
  }

  // 2. The authored-story fetcher. Copy, never rename - the fetcher's cached
  // Future keeps handing the player the original path.
  if (segment != null && fetcher != null) {
    try {
      final source = await fetcher.pathFor(segment);
      if (source != null && await File(source).exists()) {
        return _copyAtomically(source, target('mp3'));
      }
    } catch (_) {
      // Fall through to speech synthesis.
    }
  }

  // 3. On-device speech.
  final text = unit.text.trim();
  if (text.isNotEmpty) {
    final path = target(tts.fileExtension);
    final ok = await tts.synthesizeToFile(text, path);
    if (ok && await File(path).exists()) return path;
  }

  throw const ArNarrationFailure('narration_unavailable');
}

/// Writes via a temporary file so a half-written clip can never pass the
/// native validator - the temporary name is not on its allowlist.
Future<String> _writeAtomically(String path, List<int> bytes) async {
  final temporary = File('$path.tmp');
  await temporary.writeAsBytes(bytes, flush: true);
  await temporary.rename(path);
  return path;
}

Future<String> _copyAtomically(String source, String path) async {
  final temporary = File('$path.tmp');
  await File(source).copy(temporary.path);
  await temporary.rename(path);
  return path;
}

Future<void> _deleteStaleClips(Directory directory, String prefix) async {
  if (!await directory.exists()) return;
  await for (final entity in directory.list()) {
    if (entity is! File) continue;
    final name = entity.path.split(Platform.pathSeparator).last;
    if (name.startsWith('${prefix}_p')) {
      try {
        await entity.delete();
      } catch (_) {
        // A clip we cannot delete is overwritten below; not fatal.
      }
    }
  }
}
```

- [ ] **Step 4: Run the tests**

```bash
cd /Users/androidker/Projects/app-book && flutter test test/ar_narration_bundle_test.dart
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Add the production synthesizer and downloader**

Create `lib/features/ar/ar_narration_sources.dart`:

```dart
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'ar_narration_bundle.dart';

/// iOS writes through `AVAudioFile(forWriting:)`, which picks the container
/// from the extension - and iOS cannot encode MP3, so `.caf` is mandatory
/// there. Android writes WAV bytes whatever the extension, so `.wav` keeps the
/// file honest.
class FlutterTtsFileSynthesizer implements TtsFileSynthesizer {
  FlutterTtsFileSynthesizer(this._tts);

  final FlutterTts _tts;
  bool _ready = false;

  @override
  String get fileExtension => Platform.isIOS ? 'caf' : 'wav';

  @override
  Future<bool> synthesizeToFile(String text, String filePath) async {
    try {
      if (!_ready) {
        // Without this the Android call is fire-and-forget and returns before
        // the file is written, so AR would launch against a half-written clip.
        await _tts.awaitSynthCompletion(true);
        _ready = true;
      }
      await _tts.synthesizeToFile(text, filePath, true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class DioArAudioDownloader implements ArAudioDownloader {
  DioArAudioDownloader(this._dio);

  final Dio _dio;

  @override
  Future<List<int>> download(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const <int>[];
  }
}
```

> **Verify before relying on it:** the third positional argument of
> `FlutterTts.synthesizeToFile` in 4.2.5 is `isFullPath`. Check
> `~/.pub-cache/hosted/pub.dev/flutter_tts-4.2.5/lib/flutter_tts.dart` and adjust
> the call if the signature differs. Do not guess.

- [ ] **Step 6: Analyze and commit**

```bash
cd /Users/androidker/Projects/app-book
flutter analyze 2>&1 | grep 'error •' ; echo "analyze exit: $?"
git add lib/features/ar/ar_narration_bundle.dart lib/features/ar/ar_narration_sources.dart test/ar_narration_bundle_test.dart
git commit -m "feat(ar): prepare per-segment narration clips for the story reader"
```

---

### Task 4: Android - `isStoryReaderSupported` and `openStoryReader`

**Files:**
- Modify: `android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/CharacterReaderBridge.kt`
- Modify: `android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/CharacterReaderActivity.kt`
- Modify: `android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/CharacterReaderScene.kt`
- Modify: `android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/ReaderHost.kt`
- Test: `android/app/src/test/kotlin/com/storybookar/storybook_ar/characterreader/CharacterReaderBridgeTest.kt`
- Test (new): `android/app/src/test/kotlin/com/storybookar/storybook_ar/characterreader/StoryReaderPagesTest.kt`

**Interfaces:**
- Consumes: `AudioPathValidator.validate` (Task 2).
- Produces: channel methods `isStoryReaderSupported` -> `Boolean`, and `openStoryReader` -> `Map<String, Any>` with keys `terminalCode`, `lastPageId`, `pagesRead`. Intent extras `EXTRA_PAGES_JSON`, `EXTRA_INITIAL_PAGE_INDEX`; result extras `EXTRA_LAST_PAGE_ID`, `EXTRA_PAGES_READ`.

- [ ] **Step 1: Write the failing page-model test**

Create `StoryReaderPagesTest.kt`:

```kotlin
package com.storybookar.storybook_ar.characterreader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StoryReaderPagesTest {
    private fun page(id: String, vararg paths: String) =
        mapOf("pageId" to id, "pageNumber" to 1, "audioFilePaths" to paths.toList())

    @Test
    fun `parses a well formed request`() {
        val parsed = StoryReaderPages.parse(listOf(page("p1", "a.mp3", "b.mp3")))
        assertEquals(1, parsed!!.size)
        assertEquals("p1", parsed[0].pageId)
        assertEquals(listOf("a.mp3", "b.mp3"), parsed[0].audioFilePaths)
    }

    @Test
    fun `rejects a page with no audio paths`() {
        assertNull(StoryReaderPages.parse(listOf(page("p1"))))
    }

    @Test
    fun `rejects an empty page list`() {
        assertNull(StoryReaderPages.parse(emptyList<Any>()))
    }

    @Test
    fun `clamps the initial index into range`() {
        assertEquals(0, StoryReaderPages.clampIndex(-3, 2))
        assertEquals(1, StoryReaderPages.clampIndex(9, 2))
        assertEquals(1, StoryReaderPages.clampIndex(1, 2))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/androidker/Projects/app-book/android && ./gradlew :app:testDebugUnitTest --tests '*StoryReaderPagesTest*'
```

Expected: FAIL - unresolved reference `StoryReaderPages`.

- [ ] **Step 3: Add the page model**

Create `StoryReaderPages.kt` in the `characterreader` package:

```kotlin
package com.storybookar.storybook_ar.characterreader

/** One page of the story reader playlist: its clips, in narration order. */
data class StoryReaderPage(
    val pageId: String,
    val pageNumber: Int,
    val audioFilePaths: List<String>,
)

object StoryReaderPages {
    /** Returns null when the request is malformed; the bridge maps that to `audio_missing`. */
    fun parse(raw: Any?): List<StoryReaderPage>? {
        val list = raw as? List<*> ?: return null
        if (list.isEmpty()) return null
        val pages = list.map { entry ->
            val map = entry as? Map<*, *> ?: return null
            val pageId = map["pageId"] as? String ?: return null
            val pageNumber = (map["pageNumber"] as? Number)?.toInt() ?: return null
            val paths = (map["audioFilePaths"] as? List<*>)
                ?.mapNotNull { it as? String }
                ?: return null
            if (paths.isEmpty()) return null
            StoryReaderPage(pageId, pageNumber, paths)
        }
        return pages
    }

    fun clampIndex(requested: Int, size: Int): Int = requested.coerceIn(0, size - 1)
}
```

- [ ] **Step 4: Run the test**

```bash
cd /Users/androidker/Projects/app-book/android && ./gradlew :app:testDebugUnitTest --tests '*StoryReaderPagesTest*'
```

Expected: PASS.

- [ ] **Step 5: Extend the bridge**

In `CharacterReaderBridge.kt`:

1. In `handle`, replace the single `if (call.method != "openCharacterReader")` guard with a `when (call.method)` dispatching to `openCharacterReader`, `openStoryReader`, `isStoryReaderSupported`, else `notImplemented()`.
2. `isStoryReaderSupported` replies immediately with `arCore.checkAvailability() != ArCoreAvailabilityDecision.Unsupported`. It must **not** take `inProgressGate`.
3. `openStoryReader` takes the **same** `inProgressGate` as `openCharacterReader` - two readers must never be presentable at once on one channel. Parse with `StoryReaderPages.parse`; validate **every** path with `audioPathValidator.validate`; on any null, `result.error("audio_missing", null, null)`. Then run the identical ARCore availability/install flow and launch.
4. Add `finishStory(terminalCode: String, lastPageId: String?, pagesRead: List<String>)` which replies `result.success(mapOf("terminalCode" to terminalCode, "lastPageId" to lastPageId, "pagesRead" to pagesRead))`.
5. In `onActivityResult`, when the pending call is a story-reader call, read `EXTRA_LAST_PAGE_ID` and `EXTRA_PAGES_READ` and route **both** `completed` and `cancelled` through `finishStory`. Every other code still goes through `finishError`.

Point 5 is the whole reason this task exists - today only `"completed"` uses the success path, so `lastPageId` would be thrown away on cancel, and cancel is the normal way to leave AR. Concretely:

```kotlin
    /** True while the pending call came from `openStoryReader` rather than `openCharacterReader`. */
    private var pendingIsStoryReader = false

    private fun finishStory(
        terminalCode: String,
        lastPageId: String?,
        pagesRead: List<String>,
    ) {
        val result = pendingResult ?: return
        val gate = replyGate ?: return
        if (!gate.claim()) return
        clearPending()
        scheduler.runOnMain {
            result.success(
                mapOf(
                    "terminalCode" to terminalCode,
                    "lastPageId" to lastPageId,
                    "pagesRead" to pagesRead,
                ),
            )
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != readerRequestCode) return false
        if (pendingResult == null) return true

        val terminalCodeExtra =
            data?.getStringExtra(CharacterReaderResultMapper.EXTRA_TERMINAL_CODE)
        val code = CharacterReaderResultMapper.terminalCode(resultCode, terminalCodeExtra)

        if (pendingIsStoryReader) {
            // Both `completed` and `cancelled` carry progress worth keeping, so both
            // go down the success channel. result.error() is reserved for failures
            // that happened before anything was ever presented.
            if (code == CharacterReaderResultMapper.COMPLETED || code == "cancelled") {
                finishStory(
                    terminalCode = code,
                    lastPageId = data?.getStringExtra(EXTRA_LAST_PAGE_ID),
                    pagesRead = data?.getStringArrayListExtra(EXTRA_PAGES_READ)
                        ?: emptyList(),
                )
            } else {
                finishError(code)
            }
            return true
        }

        when (code) {
            CharacterReaderResultMapper.COMPLETED -> finishSuccess("completed")
            else -> finishError(code)
        }
        return true
    }
```

`clearPending()` must also reset `pendingIsStoryReader = false`.

- [ ] **Step 6: Extend the activity**

In `CharacterReaderActivity.kt`:

1. Accept `EXTRA_PAGES_JSON` (a JSON array string) and `EXTRA_INITIAL_PAGE_INDEX` alongside the existing single-file extra. When the pages extra is present, run in story mode.
2. Hold `pages: List<StoryReaderPage>`, `pageIndex: Int`, `clipIndex: Int`, and `pagesRead: LinkedHashSet<String>`.
3. `prepareAudio` targets `pages[pageIndex].audioFilePaths[clipIndex]`. On completion, advance `clipIndex`; if the page has more clips, prepare and start the next one without touching the anchor. If not, stop at "Reading complete".
4. `goToPage(delta)` clamps into range, resets `clipIndex` to 0, releases and re-prepares the MediaPlayer, and leaves the AR session and anchor untouched.
5. Record `pages[pageIndex].pageId` into `pagesRead` the first time playback starts on that page.
6. `finishWith` puts `EXTRA_LAST_PAGE_ID` = `pages[pageIndex].pageId` and `EXTRA_PAGES_READ` = `pagesRead.toList()` into the result Intent.
7. An audio failure on a page **after** the scene is showing must not call `finishWith`. Keep the existing in-scene "Audio couldn't play - Tap Retry" behaviour. Only a failure while preparing the first clip, before `showScene()`, is terminal `audio_failed`.

- [ ] **Step 7: Extend the Compose overlay**

In `CharacterReaderScene.kt`, add to `ReaderUiState`: `pageLabel: String` (e.g. `"Page 2 of 5"`), `canGoPrev: Boolean`, `canGoNext: Boolean`. Add `onPrevClick` / `onNextClick` parameters to `CharacterReaderScreen` and render prev / read-pause / next in the overlay `Row`, showing `pageLabel` when it is non-empty. **Do not touch `CharacterReaderArScene` or the anchor state** - the anchor must survive page turns, and it does so precisely because it lives in Compose state the activity never resets.

- [ ] **Step 8: Extend `ReaderHost`**

Add `launchStoryReader(pagesJson: String, initialPageIndex: Int): Boolean` next to `launchReader`, putting both extras on the Intent and using the same request code.

- [ ] **Step 9: Extend the bridge test**

Add cases to `CharacterReaderBridgeTest.kt`: `openStoryReader` with a valid playlist launches; a playlist containing one invalid path replies `audio_missing`; `openStoryReader` while `openCharacterReader` is pending replies `reader_in_progress`; a `cancelled` activity result still replies via `success` carrying `lastPageId` and `pagesRead`; `isStoryReaderSupported` replies without taking the gate.

- [ ] **Step 10: Run the Android tests and commit**

```bash
cd /Users/androidker/Projects/app-book/android && ./gradlew :app:testDebugUnitTest
```

Expected: PASS.

```bash
cd /Users/androidker/Projects/app-book
git add android/app/src
git commit -m "feat(android): add openStoryReader with in-AR page navigation"
```

---

### Task 5: iOS - `isStoryReaderSupported` and `openStoryReader`

Mirror of Task 4. Behaviour must match exactly; only the platform APIs differ.

**Files:**
- Modify: `ios/Runner/CharacterReader/CharacterReaderBridge.swift`
- Modify: `ios/Runner/CharacterReader/CharacterReaderViewController.swift`
- Test: `ios/RunnerTests/CharacterReaderTests.swift`

**Interfaces:**
- Consumes: `CharacterReaderAudioPathValidator.validate` (Task 2).
- Produces: identical channel contract to Task 4.

- [ ] **Step 1: Add the page model and parsing**

Add to `CharacterReaderBridge.swift`:

```swift
struct StoryReaderPage {
  let pageId: String
  let pageNumber: Int
  let audioURLs: [URL]

  /// Returns nil when the request is malformed or any path fails validation;
  /// the bridge maps that to `audio_missing`.
  static func parse(
    _ raw: Any?,
    validator: CharacterReaderAudioPathValidator
  ) -> [StoryReaderPage]? {
    guard let entries = raw as? [[String: Any]], !entries.isEmpty else { return nil }
    var pages: [StoryReaderPage] = []
    for entry in entries {
      guard
        let pageId = entry["pageId"] as? String,
        let pageNumber = entry["pageNumber"] as? Int,
        let paths = entry["audioFilePaths"] as? [String],
        !paths.isEmpty
      else { return nil }
      var urls: [URL] = []
      for path in paths {
        guard let url = validator.validate(path: path) else { return nil }
        urls.append(url)
      }
      pages.append(StoryReaderPage(pageId: pageId, pageNumber: pageNumber, audioURLs: urls))
    }
    return pages
  }
}
```

- [ ] **Step 2: Dispatch the two new methods**

In `handle`, replace the single `guard call.method == "openCharacterReader"` with a switch over `openCharacterReader`, `openStoryReader`, `isStoryReaderSupported`, default `FlutterMethodNotImplemented`.

`isStoryReaderSupported` returns `ARWorldTrackingConfiguration.isSupported` immediately and must not set `isReaderInProgress`.

`openStoryReader` uses the **same** `isReaderInProgress` flag, parses via `StoryReaderPage.parse`, and on nil replies `FlutterError(code: "audio_missing", ...)`.

- [ ] **Step 3: Reply on the success channel for both terminal outcomes**

The completion handler for a story reader must reply:

```swift
result([
  "terminalCode": terminalCode,   // "completed" or "cancelled"
  "lastPageId": lastPageId,
  "pagesRead": pagesRead,
])
```

`FlutterError` stays reserved for pre-presentation failures only.

- [ ] **Step 4: Extend the view controller**

Add a story-mode initializer taking `pages: [StoryReaderPage]` and `initialPageIndex: Int`. Hold `pageIndex`, `clipIndex`, `pagesRead`. Advance `clipIndex` within a page on `AVAudioPlayer` completion; `goToPage(delta)` clamps, resets `clipIndex`, swaps the player, and **leaves `AnchorEntity` untouched**. Add prev/next controls and a "Page n of N" label. Report `lastPageId` and `pagesRead` through the completion.

- [ ] **Step 5: Extend the tests**

Add `StoryReaderPage.parse` cases to `CharacterReaderTests.swift`: valid request parses; an entry with an empty `audioFilePaths` returns nil; one invalid path anywhere in the list returns nil for the whole request; an empty page list returns nil.

- [ ] **Step 6: Commit**

```bash
cd /Users/androidker/Projects/app-book
git add ios/Runner/CharacterReader ios/RunnerTests
git commit -m "feat(ios): add openStoryReader with in-AR page navigation"
```

---

### Task 6: Dart - `NativeStoryReader` and `ArReaderController`

**Files:**
- Create: `lib/features/ar/native_story_reader.dart`
- Create: `lib/features/ar/ar_reader_controller.dart`
- Test: `test/native_story_reader_test.dart`
- Test: `test/ar_reader_controller_test.dart`

**Interfaces:**
- Consumes: `ArNarrationPage.toJson()` (Task 3), the channel contract (Tasks 4-5).
- Produces:
  - `class StoryReaderResult { String terminalCode; String? lastPageId; List<String> pagesRead; }`
  - `abstract interface class StoryReader { Future<bool> isSupported(); Future<StoryReaderResult> open({required List<ArNarrationPage> pages, required int initialPageIndex}); }`
  - `class StoryReaderFailure implements Exception { String code; }`
  - `enum ArReaderPhase { idle, checkingSupport, preparing, opening, reading, failure }`
  - `class ArReaderState { ArReaderPhase phase; int prepared; int total; String? failureCode; StoryReaderResult? result; }`
  - `class ArReaderController extends ValueNotifier<ArReaderState>` with this exact constructor, which Task 7 calls verbatim:

```dart
ArReaderController({
  required StoryDetail detail,
  required StoryReader reader,
  required AssetUrlResolver resolver,
  required NarrationAudioFetcher? fetcher,
  required TtsFileSynthesizer tts,
  required ArAudioDownloader downloader,
  required Directory directory,
  required int initialPageIndex,
})
```
and one method `Future<StoryReaderResult?> start()`.

- [ ] **Step 1: Write the failing `NativeStoryReader` test**

Create `test/native_story_reader_test.dart` using `TestDefaultBinaryMessengerBinding` to stub the `storybook_ar/character_reader` channel. Assert: `isSupported` returns the channel's bool; `open` sends `pages` as a list of maps with keys `pageId`/`pageNumber`/`audioFilePaths` and `initialPageIndex` as an int; a success map parses into `StoryReaderResult`; a `PlatformException` becomes `StoryReaderFailure` carrying its code; a missing `pagesRead` key yields an empty list rather than throwing.

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/androidker/Projects/app-book && flutter test test/native_story_reader_test.dart
```

Expected: FAIL - file does not exist.

- [ ] **Step 3: Implement `NativeStoryReader`**

```dart
import 'package:flutter/services.dart';

import 'ar_narration_bundle.dart';

class StoryReaderResult {
  const StoryReaderResult({
    required this.terminalCode,
    required this.lastPageId,
    required this.pagesRead,
  });

  final String terminalCode;
  final String? lastPageId;
  final List<String> pagesRead;

  bool get completed => terminalCode == 'completed';
}

final class StoryReaderFailure implements Exception {
  const StoryReaderFailure(this.code);

  final String code;
}

abstract interface class StoryReader {
  Future<bool> isSupported();

  Future<StoryReaderResult> open({
    required List<ArNarrationPage> pages,
    required int initialPageIndex,
  });
}

final class NativeStoryReader implements StoryReader {
  NativeStoryReader({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('storybook_ar/character_reader');

  final MethodChannel _channel;

  @override
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isStoryReaderSupported') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<StoryReaderResult> open({
    required List<ArNarrationPage> pages,
    required int initialPageIndex,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'openStoryReader',
        {
          'pages': [for (final page in pages) page.toJson()],
          'initialPageIndex': initialPageIndex,
        },
      );
      return StoryReaderResult(
        terminalCode: raw?['terminalCode'] as String? ?? 'cancelled',
        lastPageId: raw?['lastPageId'] as String?,
        pagesRead:
            (raw?['pagesRead'] as List?)?.cast<String>() ?? const <String>[],
      );
    } on PlatformException catch (error) {
      throw StoryReaderFailure(error.code);
    }
  }
}
```

- [ ] **Step 4: Run the test**

```bash
cd /Users/androidker/Projects/app-book && flutter test test/native_story_reader_test.dart
```

Expected: PASS.

- [ ] **Step 5: Write the failing controller test**

Create `test/ar_reader_controller_test.dart` asserting the sequence with fakes: unsupported device -> `failure('ar_unsupported')` and the bundle is never prepared; happy path emits `checkingSupport` -> `preparing` (with progress) -> `opening` -> `reading` and exposes the result; a preparation failure yields `failure('narration_unavailable')` and the reader is never opened; a `StoryReaderFailure` yields `failure` with that code; calling `start()` twice while busy is a no-op.

- [ ] **Step 6: Implement `ArReaderController`**

Create `lib/features/ar/ar_reader_controller.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/models/models.dart';
import '../../data/sources/asset_url_resolver.dart';
import '../player/narration_audio_fetcher.dart';
import 'ar_narration_bundle.dart';
import 'native_story_reader.dart';

enum ArReaderPhase { idle, checkingSupport, preparing, opening, reading, failure }

@immutable
class ArReaderState {
  const ArReaderState({
    this.phase = ArReaderPhase.idle,
    this.prepared = 0,
    this.total = 0,
    this.failureCode,
    this.result,
  });

  final ArReaderPhase phase;
  final int prepared;
  final int total;
  final String? failureCode;
  final StoryReaderResult? result;

  ArReaderState copyWith({
    ArReaderPhase? phase,
    int? prepared,
    int? total,
    String? failureCode,
    StoryReaderResult? result,
  }) =>
      ArReaderState(
        phase: phase ?? this.phase,
        prepared: prepared ?? this.prepared,
        total: total ?? this.total,
        failureCode: failureCode ?? this.failureCode,
        result: result ?? this.result,
      );
}

/// Sequences probe -> prepare -> open -> return. Holds no Flutter widget types
/// so the whole flow is unit-testable.
class ArReaderController extends ValueNotifier<ArReaderState> {
  ArReaderController({
    required this.detail,
    required this.reader,
    required this.resolver,
    required this.fetcher,
    required this.tts,
    required this.downloader,
    required this.directory,
    required this.initialPageIndex,
  }) : super(const ArReaderState());

  final StoryDetail detail;
  final StoryReader reader;
  final AssetUrlResolver resolver;
  final NarrationAudioFetcher? fetcher;
  final TtsFileSynthesizer tts;
  final ArAudioDownloader downloader;
  final Directory directory;
  final int initialPageIndex;

  bool _busy = false;

  Future<StoryReaderResult?> start() async {
    if (_busy) return null;
    _busy = true;
    try {
      value = value.copyWith(phase: ArReaderPhase.checkingSupport);
      if (!await reader.isSupported()) {
        value = value.copyWith(
          phase: ArReaderPhase.failure,
          failureCode: 'ar_unsupported',
        );
        return null;
      }

      value = value.copyWith(phase: ArReaderPhase.preparing);
      late final List<ArNarrationPage> pages;
      try {
        pages = await prepareArNarration(
          detail: detail,
          resolver: resolver,
          fetcher: fetcher,
          tts: tts,
          downloader: downloader,
          directory: directory,
          onProgress: (done, total) =>
              value = value.copyWith(prepared: done, total: total),
        );
      } on ArNarrationFailure catch (error) {
        value = value.copyWith(
          phase: ArReaderPhase.failure,
          failureCode: error.code,
        );
        return null;
      } catch (_) {
        value = value.copyWith(
          phase: ArReaderPhase.failure,
          failureCode: 'narration_unavailable',
        );
        return null;
      }

      value = value.copyWith(phase: ArReaderPhase.opening);
      try {
        final result = await reader.open(
          pages: pages,
          initialPageIndex: initialPageIndex,
        );
        value = value.copyWith(phase: ArReaderPhase.reading, result: result);
        return result;
      } on StoryReaderFailure catch (error) {
        value = value.copyWith(
          phase: ArReaderPhase.failure,
          failureCode: error.code,
        );
        return null;
      }
    } finally {
      _busy = false;
    }
  }
}
```

- [ ] **Step 7: Run both tests and commit**

```bash
cd /Users/androidker/Projects/app-book
flutter test test/native_story_reader_test.dart test/ar_reader_controller_test.dart
flutter analyze 2>&1 | grep 'error •' ; echo "analyze exit: $?"
git add lib/features/ar/native_story_reader.dart lib/features/ar/ar_reader_controller.dart test/native_story_reader_test.dart test/ar_reader_controller_test.dart
git commit -m "feat(ar): add the story reader channel wrapper and flow controller"
```

---

### Task 7: Wire the player to the native story reader

**Files:**
- Modify: `lib/core/di.dart`
- Modify: `lib/features/player/story_player_screen.dart:186-260, 330-440`
- Create: `lib/features/ar/ar_preparing_dialog.dart`

**Interfaces:**
- Consumes: `ArReaderController`, `StoryReaderResult` (Task 6); the `NarrationAudioFetcher` instance already held by `_PlayerBodyState`.
- Produces: nothing downstream.

- [ ] **Step 1: Add the providers**

In `di.dart`, add `storyReaderProvider` (`Provider<StoryReader>` -> `NativeStoryReader()`), `ttsFileSynthesizerProvider`, and `arAudioDownloaderProvider` (built on the existing `apiClientProvider`'s Dio). Leave `characterReaderProvider` alone - scan-any-page still uses it.

- [ ] **Step 2: Resolve AR support once**

In `_PlayerBodyState`, add `bool _storyReaderSupported = false;` and resolve it in `initState` via `ref.read(storyReaderProvider).isSupported()`, `setState`-ing the result if still mounted. This is why the probe exists: without it an unsupported device shows the button, sits through the full preparation, and then fails.

- [ ] **Step 3: Replace the AR gate**

`story_player_screen.dart:194-196` becomes:

```dart
final profile = ref.watch(childProfileProvider).value;
final arAvailable = (profile?.arEnabled ?? true) && _storyReaderSupported;
```

Delete the now-unused `final arScene = widget.detail.arSceneForPage(page.id);` line. Everything else in `_PlayerControls` is unchanged.

- [ ] **Step 4: Hold the fetcher instance**

`_PlayerBodyState.initState` currently passes `ref.read(narrationAudioFetcherProvider(...))` straight into `NarrationPlayer`. Assign it to a field first:

```dart
_fetcher = _story.isAuthored
    ? ref.read(narrationAudioFetcherProvider(_story.id))
    : null;
_player = NarrationPlayer(
  resolver: ref.read(assetUrlResolverProvider),
  fetcher: _fetcher,
);
```

The provider is `autoDispose` and is read without a listener, so it is disposed after the first frame. A fresh `ref.read` inside the AR handler would build a new fetcher with an empty cache and re-issue every `POST /v1/tts`. The AR bundle must reuse **this** instance.

- [ ] **Step 5: Replace `onAr` with a blocking prepare-and-open flow**

```dart
onAr: () async {
  if (_arBusy) return;
  _arBusy = true;
  try {
    await _player.pause();
    if (!context.mounted) return;
    final result = await showArPreparingDialog(
      context,
      controller: ArReaderController(
        detail: widget.detail,
        reader: ref.read(storyReaderProvider),
        resolver: ref.read(assetUrlResolverProvider),
        fetcher: _fetcher,
        tts: ref.read(ttsFileSynthesizerProvider),
        downloader: ref.read(arAudioDownloaderProvider),
        directory: Directory.systemTemp,
        initialPageIndex: _pageIndex,
      ),
    );
    if (!mounted || result == null) return;
    await _onArReturned(result);
  } finally {
    _arBusy = false;
  }
},
```

`showArPreparingDialog` must use `barrierDismissible: false` and a `PopScope(canPop: false)`. During preparation the user must not be able to reach the player: tapping play would start in-app audio that keeps playing underneath the native AR activity, swiping would send a stale `initialPageIndex`, and popping the route would dispose `NarrationPlayer` -> `fetcher.dispose()` -> `TtsClient.dispose()`, deleting `narration_*.mp3` mid-copy.

- [ ] **Step 6: Handle the return, suppressing autoplay**

```dart
Future<void> _onArReturned(StoryReaderResult result) async {
  final sid = _sessionId;
  if (sid != null) {
    final repo = ref.read(sessionRepositoryProvider);
    for (final pageId in result.pagesRead) {
      final page = _pages.where((p) => p.id == pageId).firstOrNull;
      if (page == null) continue;
      await repo.recordEvent(
        sessionId: sid,
        eventType: 'page_viewed',
        pageId: page.id,
        payload: {'page_number': page.pageNumber, 'mode': 'ar'},
      );
    }
    if (!mounted) return;
  }

  final lastId = result.lastPageId;
  if (lastId == null) return;
  final index = _pages.indexWhere((p) => p.id == lastId);
  if (index < 0 || index == _pageIndex) return;

  // Suppressed for this one turn: _goToPage -> _onPageChanged -> _loadPage
  // autoplays, which would immediately re-narrate in the app the page the
  // character just finished reading in AR.
  _suppressNextAutoplay = true;
  _goToPage(index);
}
```

Add `bool _suppressNextAutoplay = false;` and consume it in `_onPageChanged`:

```dart
void _onPageChanged(int index) {
  setState(() => _pageIndex = index);
  final autoplay = !_suppressNextAutoplay;
  _suppressNextAutoplay = false;
  _loadPage(index, autoplay: autoplay);
}
```

Pages read inside AR never pass through `_loadPage`, which is why `pagesRead` is recorded explicitly - otherwise sessions and the parent dashboard undercount.

- [ ] **Step 7: Surface failures without blocking reading**

When `ArReaderController` ends in `ArReaderPhase.failure`, the dialog closes and the player shows a sheet built from spec section 8. AR is an enhancement; losing it must never block reading, so every branch keeps the child in the book.

```dart
String _arFailureMessage(String code) {
  switch (code) {
    case 'narration_unavailable':
      return "We couldn't get this story's voice ready for AR. "
          'You can keep reading here and try again later.';
    case 'ar_unsupported':
      return 'This device cannot show the character in AR, but the story '
          'still reads here.';
    case 'ar_unavailable':
    case 'ar_failed':
      return "We couldn't start AR this time. Your story is still here.";
    case 'model_missing':
    case 'model_load_failed':
      return "The character couldn't load. Your story is still here.";
    case 'audio_missing':
    case 'audio_failed':
      return "The character couldn't play this story's voice. "
          'You can keep reading here.';
    default:
      return "We couldn't open the character reader. Your story is still here.";
  }
}
```

The sheet offers "Try again" (re-runs `onAr`) and "Keep reading" (dismiss). `reader_in_progress` is swallowed - it means a reader is already open and is never shown to a child. `cancelled` is not a failure at all: it takes the Step 6 return path.

- [ ] **Step 8: Analyze, test, commit**

```bash
cd /Users/androidker/Projects/app-book
flutter analyze 2>&1 | grep 'error •' ; echo "analyze exit: $?"
flutter test test/narration_player_test.dart test/ar_narration_bundle_test.dart test/native_story_reader_test.dart test/ar_reader_controller_test.dart
git add lib/core/di.dart lib/features/player/story_player_screen.dart lib/features/ar/ar_preparing_dialog.dart
git commit -m "feat(player): open the native AR story reader from any story"
```

---

### Task 8: Retire the 2D AR path

**Do not start this task without re-confirming the deletion list with the user in the current session.** The spec records the decision, but a spec is not standing permission to delete.

**Files:**
- Delete: 7 files under `lib/features/ar/`, 2 source files + 2 generated files under `lib/data/`, 4 test files
- Modify: `lib/core/di.dart`, `lib/core/router/app_router.dart`, `lib/features/library/library_screen.dart`, `test/content_parsing_test.dart`

**Interfaces:**
- Consumes: Task 7's replacement of the AR route.
- Produces: nothing.

- [ ] **Step 1: Confirm nothing still references the targets**

```bash
cd /Users/androidker/Projects/app-book
grep -rn "ArStoryScreen\|ArCapabilities\|ArTrackingMode\|ScanStoryScreen\|ScanFlowController\|SimulatedPageDetector\|SimulatedPagePanel\|PageDetector\|ImageTargetResolver\|ImageTargetManifest\|imageTargetResolverProvider\|pageDetectorProvider\|arSceneForPage" --include="*.dart" lib test
```

Expected after Task 7: hits only inside the files being deleted, plus `di.dart`, `app_router.dart`, `library_screen.dart` and `content_parsing_test.dart`. **Any other hit means stop and re-plan.**

- [ ] **Step 2: Delete the files**

```bash
cd /Users/androidker/Projects/app-book
git rm lib/features/ar/ar_story_screen.dart \
       lib/features/ar/ar_scene_controller.dart \
       lib/features/ar/scan_story_screen.dart \
       lib/features/ar/scan_flow_controller.dart \
       lib/features/ar/simulated_page_detector.dart \
       lib/features/ar/page_detector.dart \
       lib/features/ar/simulated_page_panel.dart \
       lib/data/sources/image_target_resolver.dart \
       lib/data/models/image_target_manifest.dart \
       lib/data/models/image_target_manifest.freezed.dart \
       lib/data/models/image_target_manifest.g.dart \
       test/scan_flow_test.dart \
       test/simulated_page_detector_test.dart \
       test/image_target_resolver_test.dart \
       test/image_target_manifest_test.dart
```

- [ ] **Step 3: Remove the references**

- `di.dart`: delete `imageTargetResolverProvider` and `pageDetectorProvider` (lines 49-65) and their now-unused imports of `image_target_manifest.dart`, `image_target_resolver.dart`, `ar_scene_controller.dart`, `page_detector.dart`, `simulated_page_detector.dart`.
- `app_router.dart`: delete the `/story/:storyId/ar/:pageId` and `/story/:storyId/scan` routes, the `AppRoutes.ar()` and `AppRoutes.scan()` helpers (lines 30-32), and the `ar_story_screen.dart` / `scan_story_screen.dart` imports.
- `library_screen.dart`: delete the "Scan the book" `ListTile` (lines 238-247). Leave the "Read" tile.
- `content_parsing_test.dart:40`: delete the `arScenes` assertion loop. **Keep the rest of the test** - it still covers pages, segments and questions.

Do **not** touch `lib/data/models/ar_scene.dart`, `StoryDetail.arScenes`, `StoryPage.imageTargetId`, `hasImageTarget`, or `ArAnchorType.imageTarget`. These mirror backend schema that is deliberately kept; removing them would desynchronise the client model from the API for no gain.

Do **not** touch anything under `backend/` or `assets/data/`.

- [ ] **Step 4: Verify the build and the full unit suite**

```bash
cd /Users/androidker/Projects/app-book
flutter analyze 2>&1 | grep 'error •' ; echo "analyze exit: $?"
flutter test
```

Expected: analyze clean; all remaining tests PASS.

- [ ] **Step 5: Confirm the backend is untouched**

```bash
cd /Users/androidker/Projects/app-book && git status --porcelain backend/ assets/data/
```

Expected: empty output.

- [ ] **Step 6: Commit**

```bash
cd /Users/androidker/Projects/app-book
git add -A lib test
git commit -m "refactor(ar): retire the 2D scene_json AR path in favour of the native reader"
```

---

## Manual on-device verification

Not automatable, and not optional for this slice. Run after Task 7; repeat after Task 8.

- [ ] Android debug: open a recorded story, tap AR, place the character, hear page 1, navigate to page 3, close, confirm the book opens on page 3 and does not auto-narrate.
- [ ] Android release (`flutter build apk --release` then install): the same flow reaches AR and the character model loads.
- [ ] iOS: the same flow, and confirm a device-TTS page produces a `.caf` that actually plays.
- [ ] Both: confirm the anchor does not move when turning pages.
- [ ] Both: confirm scan-any-page still works end to end - `openCharacterReader` must be untouched.
