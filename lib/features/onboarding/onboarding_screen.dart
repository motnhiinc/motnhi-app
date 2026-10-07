import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/privacy_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../privacy/privacy_providers.dart';
import '../privacy/privacy_save_error.dart';
import '../profile/profile_providers.dart';

/// Parent onboarding (§7.2.1). Privacy acknowledgement and the optional
/// progress choice are submitted before the profile is saved (§14.2,
/// §14.3). Nickname optional, age band not birthdate, no photo (§14.3).
/// Microphone OFF by default (§14.1).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _profileId = const Uuid().v4();
  bool _consented = false; // required acknowledgement, starts unchecked
  bool _saving = false;

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final s = AppLocalizations.of(context)!;
    final languageCode = Localizations.localeOf(context).languageCode;
    try {
      // Submit the privacy contract, then save the
      // profile. When a prior attempt already recorded the current acceptance
      // (profile save failed afterwards), retry only the profile save.
      // Await an in-flight fetch, or retry a failed one, before using the
      // server policy. Fetch failures reach the handler with their real code.
      final privacy = await (ref.read(privacyProvider).hasError
          ? ref.refresh(privacyProvider.future)
          : ref.read(privacyProvider.future));
      if (!mounted) return;
      final consentCurrent =
          privacy.acceptedPolicyVersion != null &&
          privacy.acceptedPolicyVersion == privacy.currentPolicyVersion;
      if (!consentCurrent) {
        final policyVersion = privacy.currentPolicyVersion;
        await ref
            .read(privacyProvider.notifier)
            .updatePrivacy(
              policyVersion: policyVersion,
              coreStorageAccepted: true,
              progressTrackingEnabled: false,
              cloudTtsEnabled: true,
              pageImageValidationEnabled: true,
            );
      }
      await ref
          .read(childProfileProvider.notifier)
          .save(
            ChildProfile(
              id: _profileId,
              nickname: null,
              ageBand: AgeBand.fiveToSix,
              languageCode: languageCode == 'vi' ? 'vi' : 'en',
              arEnabled: true,
              microphoneEnabled: false,
            ),
          );
      if (mounted) context.go(AppRoutes.home);
    } on PrivacyFailure catch (e) {
      // Refresh policy state so the next retry uses fresh server truth.
      ref.invalidate(privacyProvider);
      if (mounted) showPrivacySaveError(context, s.privacySaveError, e);
    } on ProfileFailure catch (e) {
      if (e.code == 'privacy_policy_review_required') {
        // Refresh policy state; the router redirects to the review screen.
        ref.invalidate(privacyProvider);
        return;
      }
      _showError(s.profileSaveError);
    } catch (_) {
      _showError(s.setupError);
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EyebrowLabel(s.onboardingEyebrow, color: t.sage),
              const SizedBox(height: 18),
              Text(
                s.onboardingTitle,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 14),
              Text(
                s.onboardingIntro,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: t.inkMuted),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: t.sageContainer.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 11,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_stories_outlined,
                        size: 19,
                        color: t.sage,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          s.onboardingDefaultAge,
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(color: t.sage),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              PaperCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.onboardingStorageTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      s.onboardingStorageBody,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.privacyNotice),
                      style: TextButton.styleFrom(
                        foregroundColor: t.sage,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(s.privacyNoticeCta),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: t.sage,
                value: _consented,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _consented = value ?? false),
                title: Text(
                  s.consentTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              _saving
                  ? const Center(child: CircularProgressIndicator())
                  : PressablePillButton(
                      label: s.startReading,
                      height: 58,
                      onPressed: _consented ? _finish : null,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
