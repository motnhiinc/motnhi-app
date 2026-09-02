import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../data/repositories/authored_story_repository.dart';
import '../data/repositories/http_authored_story_repository.dart';
import '../data/repositories/http_privacy_repository.dart';
import '../data/repositories/http_profile_repository.dart';
import '../data/repositories/http_session_repository.dart';
import '../data/repositories/http_story_repository.dart';
import '../data/repositories/privacy_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/story_repository.dart';
import '../data/sources/api_client.dart';
import '../data/sources/asset_url_resolver.dart';
import '../data/sources/key_value_store.dart';
import '../features/ar/ar_narration_bundle.dart';
import '../features/ar/ar_narration_sources.dart';
import '../features/ar/native_story_reader.dart';
import '../features/scan_any_page/native_character_reader.dart';
import '../features/player/narration_audio_fetcher.dart';
import '../features/scan_any_page/native_scan_service.dart';
import '../features/scan_any_page/scan_any_page_controller.dart';
import '../features/scan_any_page/tts_client.dart';
import '../features/story_composer/story_composer_controller.dart';
import 'api_config.dart';

/// Provides the [KeyValueStore]. Overridden in `main()` with the instance built
/// from an initialized [SharedPreferences] so the rest of the graph stays sync.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw UnimplementedError(
    'keyValueStoreProvider must be overridden in main() with a built instance.',
  ),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    dio: Dio(BaseOptions(baseUrl: resolveApiBaseUrl())),
    store: ref.watch(keyValueStoreProvider),
  ),
);

final assetUrlResolverProvider = Provider<AssetUrlResolver>(
  (ref) => HttpAssetUrlResolver(ref.watch(apiClientProvider)),
);

final storyRepositoryProvider = Provider<StoryRepository>(
  (ref) => HttpStoryRepository(ref.watch(apiClientProvider)),
);

/// Write access for stories captured in-app (POST/DELETE /v1/stories). Reads
/// still go through [storyRepositoryProvider] — authored stories come back in
/// the normal library payload.
final authoredStoryRepositoryProvider = Provider<AuthoredStoryRepository>(
  (ref) => HttpAuthoredStoryRepository(ref.watch(apiClientProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => HttpProfileRepository(ref.watch(apiClientProvider)),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => HttpSessionRepository(ref.watch(apiClientProvider)),
);

/// Privacy & consent state (§14): policy acceptance, data toggles, deletion.
final privacyRepositoryProvider = Provider<PrivacyRepository>(
  (ref) => HttpPrivacyRepository(ref.watch(apiClientProvider)),
);

// Settings stay local — voice speed / volumes are app-local prefs, not in §10.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => LocalSettingsRepository(ref.watch(keyValueStoreProvider)),
);

final scanServiceProvider = Provider<ScanService>((ref) => NativeScanService());

final characterReaderProvider =
    Provider<CharacterReader>((ref) => NativeCharacterReader());

/// The whole-story AR reader. Shares the `character_reader` channel with
/// [characterReaderProvider]; the native side gates them behind one lock.
final storyReaderProvider =
    Provider<StoryReader>((ref) => NativeStoryReader());

/// Writes device-speech clips for pages with no real narration. Held per
/// provider rather than per call so `awaitSynthCompletion` is configured once.
final ttsFileSynthesizerProvider = Provider<TtsFileSynthesizer>(
  (ref) => FlutterTtsFileSynthesizer(FlutterTts()),
);

final arAudioDownloaderProvider = Provider<ArAudioDownloader>(
  (ref) => DioArAudioDownloader(ref.watch(apiClientProvider).dio),
);

final ttsTemporaryDirectoryProvider =
    Provider<Directory Function()?>((ref) => null);

final ttsClientProvider = Provider.autoDispose.family<TtsClient, Object>(
  (ref, flowId) => HttpTtsClient(
    ref.watch(apiClientProvider),
    temporaryDirectory: ref.watch(ttsTemporaryDirectoryProvider),
  ),
);

/// Per-story narration fetcher, used only by authored stories. autoDispose so
/// the underlying TtsClient — and every temp clip it wrote — is torn down when
/// the player leaves.
final narrationAudioFetcherProvider =
    Provider.autoDispose.family<NarrationAudioFetcher, String>((ref, storyId) {
  final fetcher = TtsNarrationAudioFetcher(
    HttpTtsClient(
      ref.watch(apiClientProvider),
      temporaryDirectory: ref.watch(ttsTemporaryDirectoryProvider),
    ),
  );
  ref.onDispose(fetcher.dispose);
  return fetcher;
});

typedef ScanAnyPageDependencies = ({
  ScanService scanService,
  CharacterReader characterReader,
  TtsClient ttsClient,
});

final scanAnyPageControllerProvider = NotifierProvider.autoDispose
    .family<ScanAnyPageController, ScanAnyPageState, ScanAnyPageDependencies>(
  (dependencies) => ScanAnyPageController(
    scanService: dependencies.scanService,
    ttsClient: dependencies.ttsClient,
    characterReader: dependencies.characterReader,
  ),
);

final storyComposerControllerProvider = NotifierProvider.autoDispose.family<
    StoryComposerController, StoryComposerState, StoryComposerDependencies>(
  (dependencies) => StoryComposerController(
    scanService: dependencies.scanService,
    repository: dependencies.repository,
    languageCode: dependencies.languageCode,
  ),
);
