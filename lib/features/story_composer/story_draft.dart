import 'package:flutter/foundation.dart';

/// One captured page held in memory while composing. Never persisted.
@immutable
class DraftPage {
  const DraftPage({required this.localId, required this.text});

  final String localId;
  final String text;

  DraftPage copyWith({String? text}) =>
      DraftPage(localId: localId, text: text ?? this.text);

  @override
  bool operator ==(Object other) =>
      other is DraftPage && other.localId == localId && other.text == text;

  @override
  int get hashCode => Object.hash(localId, text);
}

/// An in-progress authored story. Lost if the app is killed mid-capture:
/// draft persistence is deliberately out of scope for this slice.
@immutable
class StoryDraft {
  const StoryDraft({
    this.title = '',
    this.languageCode = 'en',
    this.pages = const <DraftPage>[],
  });

  final String title;
  final String languageCode;
  final List<DraftPage> pages;

  /// Save is only permitted with a real title and at least one page; the
  /// backend enforces the same rule and would answer 422 otherwise.
  bool get isSaveable => title.trim().isNotEmpty && pages.isNotEmpty;

  StoryDraft copyWith({
    String? title,
    String? languageCode,
    List<DraftPage>? pages,
  }) =>
      StoryDraft(
        title: title ?? this.title,
        languageCode: languageCode ?? this.languageCode,
        pages: pages ?? this.pages,
      );

  /// Wire format for POST /v1/stories. Page numbers come from list order, so
  /// they are always contiguous 1..N however the draft was edited — the server
  /// rejects gaps and duplicates.
  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'language_code': languageCode,
        'pages': [
          for (var i = 0; i < pages.length; i++)
            {'page_number': i + 1, 'page_text': pages[i].text.trim()},
        ],
      };

  @override
  bool operator ==(Object other) =>
      other is StoryDraft &&
      other.title == title &&
      other.languageCode == languageCode &&
      listEquals(other.pages, pages);

  @override
  int get hashCode => Object.hash(title, languageCode, Object.hashAll(pages));
}
