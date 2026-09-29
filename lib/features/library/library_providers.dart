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

/// Age/language-appropriate stories for the quiet Home shelf, unaffected by
/// the theme a child last selected in the full library.
final homeStoryShelfProvider = FutureProvider<List<Story>>((ref) async {
  final profile = ref.watch(childProfileProvider).value;
  final repo = ref.watch(storyRepositoryProvider);
  return repo.getLibrary(
    ageBand: profile?.ageBand,
    language: profile?.languageCode,
  );
});

/// The complete library, with its own optional theme filter.
final libraryProvider = FutureProvider<List<Story>>((ref) async {
  final stories = await ref.watch(homeStoryShelfProvider.future);
  final theme = ref.watch(libraryThemeFilterProvider);
  if (theme == null) return stories;
  return stories.where((s) => s.themes.contains(theme)).toList();
});
