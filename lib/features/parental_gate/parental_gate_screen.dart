import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  bool _wrong = false;

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
    final answer = int.tryParse(_controller.text.trim());
    if (answer == _a + _b) {
      ref.read(parentalGateUnlockedProvider.notifier).unlock();
      context.go(widget.redirectTo);
    } else {
      setState(() {
        _wrong = true;
        _newChallenge();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grown-ups only'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 48),
                const SizedBox(height: 16),
                Text('Ask a grown-up to continue',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Text('What is  $_a + $_b ?',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  autofocus: true,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: _wrong ? 'Not quite — try again' : null,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _submit, child: const Text('Continue')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
