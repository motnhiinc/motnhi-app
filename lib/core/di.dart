import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/image_target_manifest.dart';
import '../data/repositories/http_profile_repository.dart';
import '../data/repositories/http_session_repository.dart';
import '../data/repositories/http_story_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/story_repository.dart';
import '../data/sources/api_client.dart';
import '../data/sources/asset_url_resolver.dart';
import '../data/sources/image_target_resolver.dart';
import '../data/sources/key_value_store.dart';
import '../features/ar/ar_scene_controller.dart';
import '../features/ar/page_detector.dart';
import '../features/ar/simulated_page_detector.dart';
import '../features/scan_any_page/native_character_reader.dart';
import '../features/scan_any_page/native_scan_service.dart';
import '../features/scan_any_page/scan_any_page_controller.dart';
import '../features/scan_any_page/tts_client.dart';
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

/// Resolves a story's image-target manifest over HTTP (§5.1).
final imageTargetResolverProvider = Provider<ImageTargetResolver>(
  (ref) => HttpImageTargetResolver(ref.watch(apiClientProvider)),
);

/// Builds a [PageDetector] for a fetched manifest (§5.2 drop-in seam). While
/// native image tracking is unwired, a manifest yields a [SimulatedPageDetector];
/// a native `PageDetector` factory replaces this branch when
/// [ArCapabilities.nativeImageTrackingWired] flips to true.
final pageDetectorProvider =
    Provider<PageDetector Function(ImageTargetManifest)>((ref) {
  assert(
    !ArCapabilities.nativeImageTrackingWired,
    'Provide a native PageDetector factory once nativeImageTrackingWired is true.',
  );
  return (manifest) => SimulatedPageDetector(manifest.targets);
});

final storyRepositoryProvider = Provider<StoryRepository>(
  (ref) => HttpStoryRepository(ref.watch(apiClientProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => HttpProfileRepository(
    ref.watch(apiClientProvider),
    ref.watch(keyValueStoreProvider),
  ),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => HttpSessionRepository(ref.watch(apiClientProvider)),
);

// Settings stay local — voice speed / volumes are app-local prefs, not in §10.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => LocalSettingsRepository(ref.watch(keyValueStoreProvider)),
);

final scanServiceProvider = Provider<ScanService>((ref) => NativeScanService());

final characterReaderProvider =
    Provider<CharacterReader>((ref) => NativeCharacterReader());

final ttsTemporaryDirectoryProvider =
    Provider<Directory Function()?>((ref) => null);

final ttsClientProvider = Provider.autoDispose.family<TtsClient, Object>(
  (ref, flowId) => HttpTtsClient(
    ref.watch(apiClientProvider),
    temporaryDirectory: ref.watch(ttsTemporaryDirectoryProvider),
  ),
);

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
