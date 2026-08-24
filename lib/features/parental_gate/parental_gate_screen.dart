import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import 'parental_gate_providers.dart';

/// A simple adult-verification gate (§7.2.3). A two-number addition challenge
/// young children can't solve, protecting settings, dashboard, and any future
/// purchase/account screens. No personal data, no external calls.
class ParentalGateScreen extends ConsumerStatefulWidget {
  const ParentalGateScreen({super.key, required this.redirectTo});

  final String redirectTo;

  @override
  ConsumerState<ParentalGateScreen> createState() => _ParentalGateScreenState();
}

class _ParentalGateScreenState extends ConsumerState<ParentalGateScreen> {
  // Deterministic-but-not-trivial operands; recomputed on each wrong attempt.
  late int _a;
  late int _b;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _newChallenge();
  }

  void _newChallenge() {
    // Avoid dart:math randomness churn; derive from the current clock instead.
    final seed = DateTime.now().microsecondsSinceEpoch;
    _a = 11 + (seed % 8); // 11..18
    _b = 4 + ((seed ~/ 8) % 6); // 4..9
    _controller.clear();
  }

  void _submit() {
    final s = AppLocalizations.of(context)!;
    final answer = int.tryParse(_controller.text.trim());
    if (answer == _a + _b) {
      ref.read(parentalGateUnlockedProvider.notifier).unlock();
      context.go(widget.redirectTo);
    } else {
      setState(_newChallenge);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.gateWrong)));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => context.go(AppRoutes.home),
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
                      Icon(Icons.close_rounded, size: 20, color: t.ink),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: PaperCard(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: t.gold.withValues(alpha: .35),
                            ),
                            child: Icon(Icons.lock_outline_rounded,
                                size: 24, color: t.coralDeep),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            s.gateAsk,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: t.inputFill,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: t.line),
                            ),
                            child: Text(
                              s.gateQuestion(_a, _b),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontSize: 30),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _controller,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            textAlign: TextAlign.center,
                            autofocus: true,
                            onSubmitted: (_) => _submit(),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 18),
                          PressablePillButton(
                            label: s.gateContinue,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: 14),
                          GestureDetector(
                            onTap: () => setState(_newChallenge),
                            behavior: HitTestBehavior.opaque,
                            child: Text(
                              s.gateAnother,
                              style: TextStyle(
                                fontFamily: AppTheme.sansFamily,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: t.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
