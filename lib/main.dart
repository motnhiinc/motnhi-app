import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/di.dart';
import 'data/sources/key_value_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Build the key-value store up front so the rest of the provider graph stays
  // synchronous (see di.dart).
  final store = await KeyValueStore.create();

  runApp(
    ProviderScope(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
      child: const StorybookApp(),
    ),
  );
}
