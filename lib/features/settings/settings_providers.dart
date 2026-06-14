import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/models/models.dart';

/// Parent-controlled reading settings (§7.2.4).
final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, ReadingSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<ReadingSettings> {
  @override
  Future<ReadingSettings> build() async {
    return ref.watch(settingsRepositoryProvider).getSettings();
  }

  Future<void> edit(ReadingSettings Function(ReadingSettings) mutate) async {
    final current = state.value ?? const ReadingSettings();
    final next = mutate(current);
    await ref.read(settingsRepositoryProvider).saveSettings(next);
    state = AsyncData(next);
  }
}

/// Runtime bedtime-mode toggle (§7.1.6). Seeded from the saved default but can
/// be flipped per session without persisting.
final bedtimeModeProvider =
    NotifierProvider<BedtimeModeNotifier, bool>(BedtimeModeNotifier.new);

class BedtimeModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    final settings = ref.watch(settingsProvider).value;
    return settings?.bedtimeModeDefault ?? false;
  }

  void toggle() => state = !state;
  void set(bool value) => state = value;
}
