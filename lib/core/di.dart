import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/http_profile_repository.dart';
import '../data/repositories/http_session_repository.dart';
import '../data/repositories/http_story_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/story_repository.dart';
import '../data/sources/api_client.dart';
import '../data/sources/key_value_store.dart';

/// Backend base URL. Override at build/run time:
/// `--dart-define=API_BASE_URL=http://10.0.2.2:8000` (Android emulator) etc.
const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Provides the [KeyValueStore]. Overridden in `main()` with the instance built
/// from an initialized [SharedPreferences] so the rest of the graph stays sync.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw UnimplementedError(
    'keyValueStoreProvider must be overridden in main() with a built instance.',
  ),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    dio: Dio(BaseOptions(baseUrl: _apiBaseUrl)),
    store: ref.watch(keyValueStoreProvider),
  ),
);

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
