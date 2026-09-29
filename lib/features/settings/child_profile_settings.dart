import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';

/// Parent-only entry to the two child details deferred from onboarding.
class ChildProfileSettings extends StatelessWidget {
  const ChildProfileSettings({
    super.key,
    required this.profile,
    required this.onSave,
  });

  final ChildProfile? profile;
  final Future<void> Function(AgeBand ageBand, String? nickname) onSave;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final profile = this.profile;
    return PaperCard(
      onTap: profile == null
          ? null
          : () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _ChildProfileEditor(
                  profile: profile,
                  onSave: onSave,
                ),
              ),
      child: Row(
        children: [
          Icon(Icons.face_rounded, color: context.stitch.sage, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.childProfileTitle,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  profile == null
                      ? s.childProfileAgeHelp
                      : '${s.yearsPill(profile.ageBand.min, profile.ageBand.max)}'
                          '${profile.nickname == null ? '' : ' · ${profile.nickname}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (profile != null)
            Icon(Icons.chevron_right_rounded, color: context.stitch.inkMuted),
        ],
      ),
    );
  }
}

class _ChildProfileEditor extends StatefulWidget {
  const _ChildProfileEditor({required this.profile, required this.onSave});

  final ChildProfile profile;
  final Future<void> Function(AgeBand ageBand, String? nickname) onSave;

  @override
  State<_ChildProfileEditor> createState() => _ChildProfileEditorState();
}

class _ChildProfileEditorState extends State<_ChildProfileEditor> {
  late final TextEditingController _nickname;
  late AgeBand _ageBand;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.profile.nickname);
    _ageBand = widget.profile.ageBand;
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final nickname = _nickname.text.trim();
    try {
      await widget.onSave(_ageBand, nickname.isEmpty ? null : nickname);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.childProfileSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.childProfileTitle,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              Text(s.ageBandLabel,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(s.childProfileAgeHelp,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final band in AgeBand.values)
                    ChoiceChip(
                      label: Text(s.yearsPill(band.min, band.max)),
                      selected: _ageBand == band,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _ageBand = band),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _nickname,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: s.nicknameLabel,
                  hintText: s.nicknameHint,
                ),
              ),
              const SizedBox(height: 24),
              _saving
                  ? const Center(child: CircularProgressIndicator())
                  : PressablePillButton(
                      label: s.childProfileSave,
                      onPressed: _save,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
