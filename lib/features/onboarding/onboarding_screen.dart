import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../profile/profile_providers.dart';

/// Parent onboarding (§7.2.1). Creates a data-minimized child profile and
/// records explicit parental consent (§14.2). Nickname optional, age band not
/// birthdate, no photo (§14.3). Microphone OFF by default (§14.1).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nickname = TextEditingController();
  final _profileId = const Uuid().v4();
  AgeBand _ageBand = AgeBand.fiveToSix;
  String _language = 'en';
  bool _arEnabled = true;
  bool _microphoneEnabled = false; // off by default (§14.1)
  bool _consented = false;
  bool _saving = false;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final profileRepo = ref.read(profileRepositoryProvider);
      await profileRepo.setConsented(true);
      await ref.read(childProfileProvider.notifier).save(
            ChildProfile(
              id: _profileId,
              nickname:
                  _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
              ageBand: _ageBand,
              languageCode: _language,
              arEnabled: _arEnabled,
              microphoneEnabled: _microphoneEnabled,
            ),
          );
      if (mounted) context.go(AppRoutes.home);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.setupError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          children: [
            EyebrowLabel(s.onboardingEyebrow),
            Text(
              s.onboardingTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              s.onboardingIntro,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: t.inkMuted),
            ),
            const SizedBox(height: 22),

            // Nickname.
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.nicknameLabel,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nickname,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        InputDecoration(hintText: s.nicknameHint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Age range pills.
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.ageBandLabel,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final band in AgeBand.values)
                        _SelectPill(
                          label: s.yearsPill(band.min, band.max),
                          selected: _ageBand == band,
                          onTap: () => setState(() => _ageBand = band),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Story language pills.
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.storyLanguageLabel,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      _SelectPill(
                        label: 'English',
                        selected: _language == 'en',
                        onTap: () => setState(() => _language = 'en'),
                      ),
                      _SelectPill(
                        label: 'Tiếng Việt',
                        selected: _language == 'vi',
                        onTap: () => setState(() => _language = 'vi'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Permissions.
            PaperCard(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _arEnabled,
                onChanged: (v) => setState(() => _arEnabled = v),
                title: Text(s.arToggleOnboarding,
                    style: Theme.of(context).textTheme.titleSmall),
                subtitle: Text(s.arToggleOnboardingSub,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
            const SizedBox(height: 12),
            PaperCard(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _microphoneEnabled,
                onChanged: (v) => setState(() => _microphoneEnabled = v),
                title: Text(s.micTitle,
                    style: Theme.of(context).textTheme.titleSmall),
                subtitle: Text(s.micSub,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),

            // Consent.
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: GestureDetector(
                onTap: () => setState(() => _consented = !_consented),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: _consented ? t.coral : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.line, width: 1.5),
                      ),
                      child: _consented
                          ? const Icon(Icons.check_rounded,
                              size: 17, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.consentTitle,
                              style:
                                  Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 3),
                          Text(s.consentBody,
                              style:
                                  Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            _saving
                ? const Center(child: CircularProgressIndicator())
                : PressablePillButton(
                    label: s.startReading,
                    onPressed: _consented ? _finish : null,
                  ),
          ],
        ),
      ),
    );
  }
}

class _SelectPill extends StatelessWidget {
  const _SelectPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? t.coral : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? t.coral : t.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.sansFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : t.inkMuted,
          ),
        ),
      ),
    );
  }
}
