import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../l10n/app_localizations.dart';

/// Invoked after the child answers a question. The caller (the player's
/// session tracker) owns whether a network write is allowed (§14); the sheet
/// always advances regardless of the write outcome.
typedef QuestionAnsweredCallback = Future<void> Function({
  required String pageId,
  required String questionId,
  required String answerId,
  required bool isCorrect,
});

/// Show the questions attached to a single page.
Future<void> showPageQuestions(
  BuildContext context,
  WidgetRef ref, {
  required StoryDetail detail,
  required String pageId,
  QuestionAnsweredCallback? onAnswered,
}) {
  final questions = detail.questionsForPage(pageId);
  return _present(context, questions, onAnswered);
}

/// Show every question in the story (used at the calm completion moment).
Future<void> showStoryQuestions(
  BuildContext context,
  WidgetRef ref, {
  required StoryDetail detail,
  QuestionAnsweredCallback? onAnswered,
  Set<String> answeredQuestionIds = const {},
}) {
  return _present(
    context,
    detail.questions.where((q) => !answeredQuestionIds.contains(q.id)).toList(),
    onAnswered,
  );
}

Future<void> _present(
  BuildContext context,
  List<Question> questions,
  QuestionAnsweredCallback? onAnswered,
) {
  if (questions.isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _QuestionFlowSheet(
      questions: questions,
      onAnswered: onAnswered,
    ),
  );
}

class _QuestionFlowSheet extends StatefulWidget {
  const _QuestionFlowSheet({
    required this.questions,
    required this.onAnswered,
  });

  final List<Question> questions;
  final QuestionAnsweredCallback? onAnswered;

  @override
  State<_QuestionFlowSheet> createState() => _QuestionFlowSheetState();
}

class _QuestionFlowSheetState extends State<_QuestionFlowSheet> {
  int _index = 0;
  String? _selectedId;
  bool _answered = false;

  Question get _q => widget.questions[_index];

  Future<void> _choose(AnswerChoice choice) async {
    if (_answered) return;
    // The UI always advances; the callback (tracker) owns the network write.
    setState(() {
      _selectedId = choice.id;
      _answered = true;
    });
    final onAnswered = widget.onAnswered;
    if (onAnswered != null) {
      await onAnswered(
        pageId: _q.pageId,
        questionId: _q.id,
        answerId: choice.id,
        isCorrect: choice.isCorrect,
      );
    }
  }

  void _next() {
    if (_index < widget.questions.length - 1) {
      setState(() {
        _index++;
        _selectedId = null;
        _answered = false;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isLast = _index == widget.questions.length - 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.questionCounter(_index + 1, widget.questions.length),
            style: theme.textTheme.labelMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(_q.prompt,
              style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: _q.choices.length <= 2 ? 2 : 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
            children: [
              for (final choice in _q.choices)
                _ChoiceTile(
                  choice: choice,
                  selected: _selectedId == choice.id,
                  answered: _answered,
                  onTap: () => _choose(choice),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_answered)
            FilledButton(
              onPressed: _next,
              child: Text(isLast ? s.doneLabel : s.nextLabel),
            ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.choice,
    required this.selected,
    required this.answered,
    required this.onTap,
  });

  final AnswerChoice choice;
  final bool selected;
  final bool answered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Reveal correctness only after answering, never punitively.
    Color border = scheme.outlineVariant;
    Color fill = scheme.surfaceContainerHighest;
    if (answered) {
      if (choice.isCorrect) {
        border = Colors.green;
        fill = Colors.green.withValues(alpha: 0.12);
      } else if (selected) {
        border = scheme.error;
        fill = scheme.errorContainer.withValues(alpha: 0.4);
      }
    } else if (selected) {
      border = scheme.primary;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: border, width: 2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (choice.imageAsset != null && choice.imageAsset!.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    choice.imageAsset!,
                    errorBuilder: (_, _, _) => _glyph(choice.emoji ?? '❓'),
                  ),
                ),
              )
            else
              Expanded(child: _glyph(choice.emoji ?? '❓')),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(choice.label,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glyph(String emoji) =>
      Center(child: Text(emoji, style: const TextStyle(fontSize: 48)));
}
