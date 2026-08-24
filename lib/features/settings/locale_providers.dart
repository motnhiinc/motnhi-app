import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';

const _storageKey = 'ui_locale_override';

/// UI-language override chosen in Settings. Null = follow the system locale.
/// Story *content* language remains the child profile's `languageCode`.
final localeOverrideProvider =
    NotifierProvider<LocaleOverrideNotifier, Locale?>(
  LocaleOverrideNotifier.new,
);

class LocaleOverrideNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    final code = ref.watch(keyValueStoreProvider).getString(_storageKey);
    return code == null ? null : Locale(code);
  }

  Future<void> set(Locale? locale) async {
    state = locale;
    final store = ref.read(keyValueStoreProvider);
    if (locale == null) {
      await store.remove(_storageKey);
    } else {
      await store.setString(_storageKey, locale.languageCode);
    }
  }
}
