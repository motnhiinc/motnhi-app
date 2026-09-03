import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/models/models.dart';
import '../../data/sources/persistence_keys.dart';

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

/// Parent-set daily reading-time ceiling, in minutes (design mockup §7.2.4).
/// Persisted locally; enforcement lands with the screen-time slice — the
/// control ships now so parents can express intent early.
final dailyLimitMinutesProvider =
    NotifierProvider<DailyLimitMinutesNotifier, int>(
  DailyLimitMinutesNotifier.new,
);

class DailyLimitMinutesNotifier extends Notifier<int> {
  static const options = [15, 45, 120];

  @override
  int build() {
    final raw = ref.watch(keyValueStoreProvider).getString(
          settingsDailyLimitMinutesKey,
        );
    final parsed = raw == null ? null : int.tryParse(raw);
    return parsed ?? 45;
  }

  Future<void> set(int minutes) async {
    state = minutes;
    await ref
        .read(keyValueStoreProvider)
        .setString(settingsDailyLimitMinutesKey, '$minutes');
  }
}

/// Coarse age band for recommendations ("content filter" mockup control).
enum ContentFilterBand { preschool, primary, explorer }

final contentFilterBandProvider =
    NotifierProvider<ContentFilterBandNotifier, ContentFilterBand>(
  ContentFilterBandNotifier.new,
);

class ContentFilterBandNotifier extends Notifier<ContentFilterBand> {
  @override
  ContentFilterBand build() {
    final raw = ref
        .watch(keyValueStoreProvider)
        .getString(settingsContentFilterBandKey);
    return ContentFilterBand.values.where((b) => b.name == raw).firstOrNull ??
        ContentFilterBand.primary;
  }

  Future<void> set(ContentFilterBand band) async {
    state = band;
    await ref
        .read(keyValueStoreProvider)
        .setString(settingsContentFilterBandKey, band.name);
  }
}

/// Learning-report notifications opt-in (mockup control; delivery later).
final notificationsEnabledProvider =
    NotifierProvider<NotificationsEnabledNotifier, bool>(
  NotificationsEnabledNotifier.new,
);

class NotificationsEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref
      .watch(keyValueStoreProvider)
      .getBool(settingsNotificationsEnabledKey, fallback: false);

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(keyValueStoreProvider)
        .setBool(settingsNotificationsEnabledKey, value);
  }
}
