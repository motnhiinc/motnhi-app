import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the parental gate is currently passed (§7.2.3). Resets to false
/// whenever the app returns to child surfaces, so the gate is re-challenged
/// each time a parent enters settings/dashboard/payments.
final parentalGateUnlockedProvider =
    NotifierProvider<ParentalGateNotifier, bool>(ParentalGateNotifier.new);

class ParentalGateNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;
  void lock() => state = false;
}
