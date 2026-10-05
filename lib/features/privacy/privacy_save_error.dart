import 'package:flutter/material.dart';

import '../../data/repositories/privacy_repository.dart';

/// Keep first-run consent failures visible for a customer screenshot without
/// exposing response bodies, request headers, or device credentials.
void showPrivacySaveError(
  BuildContext context,
  String message,
  PrivacyFailure failure,
) {
  final code = RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(failure.code)
      ? failure.code
      : 'server_error';
  final status = failure.statusCode;
  debugPrint('Privacy save failed: code=$code, status=$status');
  final detail = status == null ? code : '$code, HTTP $status';
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text('$message ($detail)'),
    duration: const Duration(seconds: 15),
  ));
}
