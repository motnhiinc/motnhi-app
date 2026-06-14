import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../profile/profile_providers.dart';
import 'settings_providers.dart';

/// Parent-controlled reading + safety settings (§7.2.4). Audio/pacing live in
/// [ReadingSettings]; AR and microphone permissions live on the child profile
/// (single source of truth, gated here).
class ReadingSettingsScreen extends ConsumerWidget {
  const ReadingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ??
        const ReadingSettings();
    final profile = ref.watch(childProfileProvider).value;
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final profileNotifier = ref.read(childProfileProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(AppRoutes.parent),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'Voice & sound'),
          _SliderTile(
            label: 'Voice speed',
            value: settings.voiceSpeed,
            min: 0.6,
            max: 1.4,
            display: '${settings.voiceSpeed.toStringAsFixed(2)}×',
            onChanged: (v) =>
                settingsNotifier.edit((s) => s.copyWith(voiceSpeed: v)),
          ),
          _SliderTile(
            label: 'Sound effects',
            value: settings.soundEffectsVolume,
            min: 0,
            max: 1,
            display: '${(settings.soundEffectsVolume * 100).round()}%',
            onChanged: (v) => settingsNotifier
                .edit((s) => s.copyWith(soundEffectsVolume: v)),
          ),
          _SliderTile(
            label: 'Background music',
            value: settings.backgroundMusicVolume,
            min: 0,
            max: 1,
            display: '${(settings.backgroundMusicVolume * 100).round()}%',
            onChanged: (v) => settingsNotifier
                .edit((s) => s.copyWith(backgroundMusicVolume: v)),
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'Reading'),
          ListTile(
            title: const Text('Story language'),
            trailing: DropdownButton<String>(
              value: settings.languageCode,
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'vi', child: Text('Tiếng Việt')),
              ],
              onChanged: (v) => settingsNotifier
                  .edit((s) => s.copyWith(languageCode: v ?? 'en')),
            ),
          ),
          SwitchListTile(
            title: const Text('Start in bedtime mode'),
            subtitle: const Text('Calmer pacing and a darker, dimmer screen.'),
            value: settings.bedtimeModeDefault,
            onChanged: (v) => settingsNotifier
                .edit((s) => s.copyWith(bedtimeModeDefault: v)),
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'Safety & permissions'),
          SwitchListTile(
            title: const Text('AR camera scenes'),
            subtitle: const Text('Characters appear over the page.'),
            value: profile?.arEnabled ?? true,
            onChanged: profile == null
                ? null
                : (v) =>
                    profileNotifier.edit((p) => p.copyWith(arEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Microphone'),
            subtitle: const Text('Off by default. Only for voice answers.'),
            value: profile?.microphoneEnabled ?? false,
            onChanged: profile == null
                ? null
                : (v) => profileNotifier
                    .edit((p) => p.copyWith(microphoneEnabled: v)),
          ),
          const SizedBox(height: 16),
          const _PrivacyNote(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      );
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
            Text(label),
            Text(display, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.privacy_tip_outlined, size: 20),
                const SizedBox(width: 8),
                Text('Your privacy',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Reading progress is stored only on this device. We never collect '
              "your child's real name, birthday, photo, voice, or camera images.",
            ),
          ],
        ),
      ),
    );
  }
}
