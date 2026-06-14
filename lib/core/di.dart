import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/profile_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/story_repository.dart';
import '../data/sources/key_value_store.dart';
import '../data/sources/local_content_source.dart';

/// Provides the [KeyValueStore]. Overridden in `main()` with the instance built
/// from an initialized [SharedPreferences] so the rest of the graph stays sync.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw UnimplementedError(
    'keyValueStoreProvider must be overridden in main() with a built instance.',
  ),
);

final localContentSourceProvider = Provider<LocalContentSource>(
  (ref) => LocalContentSource(),
);

final storyRepositoryProvider = Provider<StoryRepository>(
  (ref) => LocalStoryRepository(ref.watch(localContentSourceProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => LocalProfileRepository(ref.watch(keyValueStoreProvider)),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => LocalSessionRepository(ref.watch(keyValueStoreProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => LocalSettingsRepository(ref.watch(keyValueStoreProvider)),
);
