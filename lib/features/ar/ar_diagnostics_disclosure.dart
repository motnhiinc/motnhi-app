import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'ar_reader_diagnostic.dart';

class ArDiagnosticsDisclosure extends StatelessWidget {
  const ArDiagnosticsDisclosure({
    super.key,
    required this.diagnostic,
  });

  final ArReaderDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return ExpansionTile(
      key: const ValueKey('ar-technical-details'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
      title: Text(s.arTechnicalDetails),
      children: [
        if (diagnostic.availability != null)
          _DiagnosticValue(
            label: s.arDiagnosticAvailability,
            value: diagnostic.availability!,
          ),
        if (diagnostic.decision != null)
          _DiagnosticValue(
            label: s.arDiagnosticDecision,
            value: diagnostic.decision!,
          ),
        if (diagnostic.cause != null)
          _DiagnosticValue(
            label: s.arDiagnosticCause,
            value: diagnostic.cause!,
          ),
      ],
    );
  }
}

class _DiagnosticValue extends StatelessWidget {
  const _DiagnosticValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SelectableText('$label: $value'),
      );
}
