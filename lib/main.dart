import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/di.dart';
import 'data/sources/key_value_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Build the key-value store up front so the rest of the provider graph stays
  // synchronous (see di.dart).
  final store = await KeyValueStore.create();
  final cachedCacheDir =
      Platform.isAndroid ? await getTemporaryDirectory() : null;

  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        ttsTemporaryDirectoryProvider.overrideWithValue(
          Platform.isAndroid && cachedCacheDir != null
              ? () => cachedCacheDir
              : null,
        ),
      ],
      child: const StorybookApp(),
    ),
  );
}
