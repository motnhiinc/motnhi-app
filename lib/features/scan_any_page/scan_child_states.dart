import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';

/// Child-safe handoff when page upload and narration are not parent-enabled.
class ScanGrownUpHandoff extends StatelessWidget {
  const ScanGrownUpHandoff({
    super.key,
    required this.readyToRetry,
    required this.onBack,
    required this.onPrimary,
    required this.onPickStory,
  });

  final bool readyToRetry;
  final VoidCallback onBack;
  final VoidCallback onPrimary;
  final VoidCallback onPickStory;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(s.back),
                ),
              ),
              const SizedBox(height: 110),
              Container(
                width: 250,
                height: 235,
                decoration: BoxDecoration(
                  color: t.sageContainer.withValues(alpha: .32),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.auto_stories_rounded, size: 135, color: t.sage),
                    Positioned(
                      top: 32,
                      child:
                          Icon(Icons.shield_rounded, size: 80, color: t.coral),
                    ),
                    const Positioned(
                      top: 58,
                      child: Icon(Icons.lock_outline_rounded,
                          size: 26, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                readyToRetry ? s.scanReadyTitle : s.scanGrownUpTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.sansFamily,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                readyToRetry ? s.scanReadyBody : s.scanGrownUpBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 66),
              PressablePillButton(
                label: readyToRetry ? s.scanMyBook : s.scanAskGrownUp,
                height: 62,
                onPressed: onPrimary,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onPickStory,
                child: Text(s.scanPickStoryInstead),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-message state for preparation and recoverable/unreadable pages.
class ScanChildState extends StatelessWidget {
  const ScanChildState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 70),
          Container(
            width: 150,
            height: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.sageContainer.withValues(alpha: .3),
            ),
            child: loading
                ? CircularProgressIndicator(color: t.sage)
                : Icon(icon, size: 76, color: t.sage),
          ),
          const SizedBox(height: 30),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.sansFamily,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              color: t.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 70),
          if (primaryLabel != null)
            PressablePillButton(
                label: primaryLabel!, height: 62, onPressed: onPrimary),
          if (secondaryLabel != null) ...[
            const SizedBox(height: 10),
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ],
      ),
    );
  }
}
