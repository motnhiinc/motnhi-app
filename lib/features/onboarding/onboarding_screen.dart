import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
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
          const SnackBar(
            content: Text(
              'Could not finish setup. Check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome, grown-ups')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Set up a safe space to read',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'We collect only what we need: an age range and language. '
              'No real name, no birthday, no photo. The microphone stays off '
              'unless you turn it on.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Text("Child's nickname (optional)",
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _nickname,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. Little Star',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text('Age range', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<AgeBand>(
              segments: [
                for (final band in AgeBand.values)
                  ButtonSegment(value: band, label: Text(band.label)),
              ],
              selected: {_ageBand},
              onSelectionChanged: (s) => setState(() => _ageBand = s.first),
            ),
            const SizedBox(height: 24),
            Text('Story language', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'vi', child: Text('Tiếng Việt')),
              ],
              onChanged: (v) => setState(() => _language = v ?? 'en'),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _arEnabled,
              onChanged: (v) => setState(() => _arEnabled = v),
              title: const Text('Allow AR camera scenes'),
              subtitle: const Text(
                  'Characters appear over the page. You can change this later.'),
            ),
            SwitchListTile(
              value: _microphoneEnabled,
              onChanged: (v) => setState(() => _microphoneEnabled = v),
              title: const Text('Allow microphone'),
              subtitle:
                  const Text('Off by default. Only needed for voice answers.'),
            ),
            const Divider(height: 32),
            CheckboxListTile(
              value: _consented,
              onChanged: (v) => setState(() => _consented = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I am the parent or guardian and I consent'),
              subtitle: const Text(
                  'I consent to creating this child profile and storing reading '
                  'progress on this device.'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _consented && !_saving ? _finish : null,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Start reading'),
            ),
          ],
        ),
      ),
    );
  }
}
