import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';

/// Read-only, scrollable full privacy notice (§14). Localized sections cover
/// stored data, the optional progress choice, cloud narration/ElevenLabs,
/// camera/scan handling, retention, deletion, and the retained anonymous
/// device identity.
class PrivacyNoticeScreen extends ConsumerWidget {
  const PrivacyNoticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;

    final sections = [
      (s.privacyStoredTitle, s.privacyStorageRequiredBody),
      (s.privacyTrackingTitle, s.privacyTrackingBody),
      (s.privacyCloudTitle, s.privacyCloudBody),
      (s.privacyPageImageTitle, s.privacyPageImageBody),
      (s.privacyCameraTitle, s.privacyCameraBody),
      (s.privacyRetentionTitle, s.privacyRetentionBody),
      (s.privacyDeletionTitle, s.privacyDeletionBody),
      (s.privacyDeviceIdentityTitle, s.privacyDeviceIdentityBody),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(s.privacyNoticeTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          children: [
            Text(
              s.privacyNoticeIntro,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: t.inkMuted),
            ),
            const SizedBox(height: 20),
            for (final (title, body) in sections) ...[
              PaperCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(body, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
