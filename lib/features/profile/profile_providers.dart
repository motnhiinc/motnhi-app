import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/models/models.dart';

/// The active child profile (§9.5.2). Null until onboarding completes.
final childProfileProvider =
    AsyncNotifierProvider<ChildProfileNotifier, ChildProfile?>(
  ChildProfileNotifier.new,
);

class ChildProfileNotifier extends AsyncNotifier<ChildProfile?> {
  @override
  Future<ChildProfile?> build() async {
    return ref.watch(profileRepositoryProvider).getProfile();
  }

  Future<void> save(ChildProfile profile) async {
    await ref.read(profileRepositoryProvider).saveProfile(profile);
    state = AsyncData(profile);
  }

  Future<void> edit(ChildProfile Function(ChildProfile) mutate) async {
    final current = state.value;
    if (current == null) return;
    await save(mutate(current));
  }
}

/// Whether onboarding (consent + profile) is complete (§7.2.1, §14.2).
final isOnboardedProvider = Provider<bool>((ref) {
  final profile = ref.watch(childProfileProvider).value;
  final consented = ref.watch(profileRepositoryProvider).hasConsented;
  return consented && profile != null;
});
