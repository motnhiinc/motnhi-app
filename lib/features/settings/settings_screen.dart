import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../profile/profile_providers.dart';
import '../privacy/privacy_providers.dart';
import 'locale_providers.dart';
import 'settings_providers.dart';

/// Parent-controlled reading + safety settings (§7.2.4). Audio/pacing live in
/// [ReadingSettings]; AR and microphone permissions live on the child profile
/// (single source of truth, gated here). The mockup's time-limit, content
/// filter, notifications, and app-language controls persist locally.
class ReadingSettingsScreen extends ConsumerWidget {
  const ReadingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;
    final settings =
        ref.watch(settingsProvider).value ?? const ReadingSettings();
    final profile = ref.watch(childProfileProvider).value;
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final profileNotifier = ref.read(childProfileProvider.notifier);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => context.go(AppRoutes.parent),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.paper,
                      border: Border.all(color: t.line),
                    ),
                    child:
                        Icon(Icons.arrow_back_rounded, size: 20, color: t.ink),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.settingsTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(s.readingSafetyTitle,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(s.readingSafetySub,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: t.inkMuted)),
            const SizedBox(height: 22),

            // Reading time limit (pills; enforcement lands with screen-time).
            PaperCard(
              child: Builder(
                builder: (context) {
                  final s = AppLocalizations.of(context)!;
                  final limit = ref.watch(dailyLimitMinutesProvider);
                  final notifier =
                      ref.read(dailyLimitMinutesProvider.notifier);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingTitle(s.timeLimitTitle),
                      const SizedBox(height: 3),
                      Text(s.timeLimitBody,
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final minutes
                              in DailyLimitMinutesNotifier.options)
                            _PillChip(
                              label: s.minutesShort(minutes),
                              selected: limit == minutes,
                              onTap: () => notifier.set(minutes),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),

            // Content filter bands.
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingTitle(s.contentFilterTitle),
                  const SizedBox(height: 3),
                  Text(s.contentFilterBody,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Builder(builder: (context) {
                    final band = ref.watch(contentFilterBandProvider);
                    final notifier =
                        ref.read(contentFilterBandProvider.notifier);
                    String label(ContentFilterBand b) => switch (b) {
                          ContentFilterBand.preschool => s.bandPreschool,
                          ContentFilterBand.primary => s.bandPrimary,
                          ContentFilterBand.explorer => s.bandExplorer,
                        };
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final b in ContentFilterBand.values)
                          _PillChip(
                            label: label(b),
                            selected: band == b,
                            onTap: () => notifier.set(b),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            ),

            // Notifications opt-in.
            PaperCard(
              child: _SwitchRow(
                title: s.notificationsTitle,
                subtitle: s.notificationsBody,
                value: ref.watch(notificationsEnabledProvider),
                onChanged: (v) =>
                    ref.read(notificationsEnabledProvider.notifier).set(v),
              ),
            ),

            // Voice & sound (existing ReadingSettings sliders).
            const SizedBox(height: 26),
            _SectionLabel(s.voiceSoundSection),
            PaperCard(
              child: _SliderTile(
                label: s.voiceSpeedLabel,
                value: settings.voiceSpeed,
                min: 0.6,
                max: 1.4,
                display: '${settings.voiceSpeed.toStringAsFixed(2)}×',
                onChanged: (v) =>
                    settingsNotifier.edit((x) => x.copyWith(voiceSpeed: v)),
              ),
            ),
            PaperCard(
              child: _SliderTile(
                label: s.sfxVolumeLabel,
                value: settings.soundEffectsVolume,
                min: 0,
                max: 1,
                display: '${(settings.soundEffectsVolume * 100).round()}%',
                onChanged: (v) => settingsNotifier
                    .edit((x) => x.copyWith(soundEffectsVolume: v)),
              ),
            ),
            PaperCard(
              child: _SliderTile(
                label: s.musicVolumeLabel,
                value: settings.backgroundMusicVolume,
                min: 0,
                max: 1,
                display:
                    '${(settings.backgroundMusicVolume * 100).round()}%',
                onChanged: (v) => settingsNotifier
                    .edit((x) => x.copyWith(backgroundMusicVolume: v)),
              ),
            ),

            // Story content language (child profile consumption language).
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingTitle(s.storyLanguageLabel),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      _PillChip(
                        label: 'English',
                        selected: settings.languageCode == 'en',
                        onTap: () => settingsNotifier
                            .edit((x) => x.copyWith(languageCode: 'en')),
                      ),
                      _PillChip(
                        label: 'Tiếng Việt',
                        selected: settings.languageCode == 'vi',
                        onTap: () => settingsNotifier
                            .edit((x) => x.copyWith(languageCode: 'vi')),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // UI chrome language (system default + manual override).
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingTitle(s.appLanguageLabel),
                  const SizedBox(height: 10),
                  Builder(builder: (context) {
                    final override = ref.watch(localeOverrideProvider);
                    final notifier = ref.read(localeOverrideProvider.notifier);
                    return Wrap(
                      spacing: 8,
                      children: [
                        _PillChip(
                          label: s.languageSystem,
                          selected: override == null,
                          onTap: () => notifier.set(null),
                        ),
                        _PillChip(
                          label: 'English',
                          selected: override?.languageCode == 'en',
                          onTap: () => notifier.set(const Locale('en')),
                        ),
                        _PillChip(
                          label: 'Tiếng Việt',
                          selected: override?.languageCode == 'vi',
                          onTap: () => notifier.set(const Locale('vi')),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),

            // Bedtime default (existing).
            PaperCard(
              child: _SwitchRow(
                icon: Icons.dark_mode_rounded,
                iconColor: t.lavender,
                title: s.bedtimeDefaultTitle,
                subtitle: s.bedtimeDefaultSub,
                value: settings.bedtimeModeDefault,
                onChanged: (v) =>
                    settingsNotifier.edit((x) => x.copyWith(bedtimeModeDefault: v)),
              ),
            ),

            // Safety & permissions (child profile, gated here).
            PaperCard(
              child: _SwitchRow(
                title: s.arScenesTitle,
                subtitle: s.arScenesSub,
                value: profile?.arEnabled ?? true,
                onChanged: profile == null
                    ? null
                    : (v) => profileNotifier.edit((p) => p.copyWith(arEnabled: v)),
              ),
            ),
            PaperCard(
              child: _SwitchRow(
                title: s.micTitle,
                subtitle: s.micSub,
                value: profile?.microphoneEnabled ?? false,
                onChanged: profile == null
                    ? null
                    : (v) =>
                        profileNotifier.edit((p) => p.copyWith(microphoneEnabled: v)),
              ),
            ),

            // Account (mockup row; management ships with accounts slice).
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: PaperCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.comingSoonToast)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_circle_rounded,
                        size: 22, color: t.lavender),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(s.manageAccount,
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 22, color: t.inkMuted),
                  ],
                ),
              ),
            ),

            // Privacy & data (live server state; opens /parent/privacy).
            const SizedBox(height: 12),
            PaperCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              onTap: () => context.push(AppRoutes.parentPrivacy),
              child: Builder(
                builder: (context) {
                  final s = AppLocalizations.of(context)!;
                  final privacy = ref.watch(privacyProvider).value;
                  final trackingSummary = (privacy?.progressTrackingEnabled ??
                          false)
                      ? s.privacySettingsSummaryTrackingOn
                      : s.privacySettingsSummaryTrackingOff;
                  final cloudSummary =
                      (privacy?.cloudTtsEnabled ?? false)
                          ? s.privacySettingsSummaryCloudOn
                          : s.privacySettingsSummaryCloudOff;
                  return Row(
                    children: [
                      Icon(Icons.privacy_tip_outlined, size: 22, color: t.sage),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.privacyTitle,
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              privacy == null
                                  ? s.privacySettingsManageBody
                                  : '$trackingSummary · $cloudSummary',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 22, color: t.inkMuted),
                    ],
                  );
                },
              ),
            ),

            // Settings apply immediately; Save confirms out loud for parents.
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: PressablePillButton(
                label: s.saveChanges,
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.savedToast)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: EyebrowLabel(text, color: Theme.of(context).colorScheme.onSurface),
    );
  }
}

class _SettingTitle extends StatelessWidget {
  const _SettingTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleSmall);
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
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
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
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
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : t.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
    this.iconColor,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 21, color: iconColor ?? context.stitch.inkMuted),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            Text(display, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: context.stitch.coral,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
