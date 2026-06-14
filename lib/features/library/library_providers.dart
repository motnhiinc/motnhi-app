import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/models/models.dart';
import '../profile/profile_providers.dart';

/// Currently selected theme filter (§7.1.1). Null = all themes.
final libraryThemeFilterProvider =
    NotifierProvider<LibraryThemeFilter, StoryTheme?>(LibraryThemeFilter.new);

class LibraryThemeFilter extends Notifier<StoryTheme?> {
  @override
  StoryTheme? build() => null;

  void select(StoryTheme? theme) => state = theme;
}

/// The library list for the active child, filtered by age band, language, and
/// the selected theme (§11.1, §7.1.1).
final libraryProvider = FutureProvider<List<Story>>((ref) async {
  final profile = ref.watch(childProfileProvider).value;
  final repo = ref.watch(storyRepositoryProvider);
  final stories = await repo.getLibrary(
    ageBand: profile?.ageBand,
    language: profile?.languageCode,
  );
  final theme = ref.watch(libraryThemeFilterProvider);
  if (theme == null) return stories;
  return stories.where((s) => s.themes.contains(theme)).toList();
});
