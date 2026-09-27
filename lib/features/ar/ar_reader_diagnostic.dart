/// Android ARCore details retained when the native character reader cannot start.
///
/// This is diagnostic metadata only; the user-facing failure remains localized
/// and is driven by the stable failure code.
class ArReaderDiagnostic {
  const ArReaderDiagnostic({
    this.availability,
    this.decision,
    this.cause,
  });

  final String? availability;
  final String? decision;
  final String? cause;

  @override
  bool operator ==(Object other) =>
      other is ArReaderDiagnostic &&
      other.availability == availability &&
      other.decision == decision &&
      other.cause == cause;

  @override
  int get hashCode => Object.hash(availability, decision, cause);

  static ArReaderDiagnostic? fromWire(Object? value) {
    if (value is! Map) return null;

    String? readString(String key) {
      final field = value[key];
      return field is String && field.isNotEmpty ? field : null;
    }

    final diagnostic = ArReaderDiagnostic(
      availability: readString('availability'),
      decision: readString('decision'),
      cause: readString('cause'),
    );
    if (diagnostic.availability == null &&
        diagnostic.decision == null &&
        diagnostic.cause == null) {
      return null;
    }
    return diagnostic;
  }
}
