import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/di.dart';
import 'data/sources/key_value_store.dart';
import 'data/sources/persistence_keys.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Build the key-value store up front so the rest of the provider graph stays
  // synchronous (see di.dart).
  final store = await KeyValueStore.create();
  final cachedCacheDir =
      Platform.isAndroid ? await getTemporaryDirectory() : null;

  // The container is created explicitly so the Task 20 bootstrap repair can
  // run against the same graph the app will use.
  final container = ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      ttsTemporaryDirectoryProvider.overrideWithValue(
        Platform.isAndroid && cachedCacheDir != null
            ? () => cachedCacheDir
            : null,
      ),
    ],
  );

  // Task 20 bootstrap repair: a leftover cleanup marker (or post-deletion
  // residue) is repaired BEFORE access routing — the router below is only
  // created after this completes, so access derivation never sees stale
  // child state.
  try {
    await repairPendingChildDataCleanup(container);
  } catch (_) {
    // A failed repair must not brick startup: the pending marker stays and
    // the next launch retries.
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const StorybookApp(),
    ),
  );
}

/// Task 20 bootstrap repair, awaited before router creation in [main].
///
/// 1. A pending cleanup marker means a previous cleanup was interrupted:
///    finish it (no server round-trip needed).
/// 2. Without a marker, residue (any child key or owned generated-audio file)
///    is only cleaned when the server confirms a fresh null-policy row with
///    no profile — i.e. child data was deleted server-side but local cleanup
///    never ran. Any server failure keeps local data (fail-closed).
Future<void> repairPendingChildDataCleanup(
  ProviderContainer container,
) async {
  final store = container.read(keyValueStoreProvider);
  final cleaner = container.read(childDataCleanerProvider);

  if (store.getBool(childCleanupPendingKey)) {
    await cleaner.clean();
    return;
  }

  final residue = store.keys.any(childDataKeys.contains) ||
      await cleaner.hasOwnedAudioFiles();
  if (!residue) return;
  try {
    final privacy =
        await container.read(privacyRepositoryProvider).fetchPrivacy();
    if (privacy.acceptedPolicyVersion != null) return;
    final profile =
        await container.read(profileRepositoryProvider).getProfile();
    if (profile != null) return;
    await cleaner.clean();
  } catch (_) {
    // Server state unconfirmed (offline/error): never delete local data.
  }
}
