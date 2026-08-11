import 'dart:io';

import 'package:flutter/foundation.dart';

const _debugApiBaseUrl = 'http://localhost:8000';

String resolveApiBaseUrl({
  String configuredUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _debugApiBaseUrl,
  ),
  bool isRelease = kReleaseMode,
}) {
  if (!isRelease) {
    return configuredUrl.isEmpty ? _debugApiBaseUrl : configuredUrl;
  }

  final uri = Uri.tryParse(configuredUrl);
  final host = uri?.host.toLowerCase() ?? '';
  final validationHost = host.replaceFirst(RegExp(r'\.+$'), '');

  if (uri == null ||
      uri.scheme != 'https' ||
      validationHost.isEmpty ||
      _isLoopbackHost(validationHost)) {
    throw StateError(
      'API_BASE_URL must be an explicit HTTPS URL with a non-loopback host. '
      'Configure it with --dart-define=API_BASE_URL=https://api.example.com',
    );
  }

  return configuredUrl;
}

bool _isLoopbackHost(String host) {
  if (host == 'localhost') {
    return true;
  }

  final address = InternetAddress.tryParse(host);
  if (address?.isLoopback ?? false) {
    return true;
  }

  final rawAddress = address?.rawAddress;
  final isMappedIpv4Loopback = rawAddress != null &&
      rawAddress.length == 16 &&
      rawAddress.take(10).every((byte) => byte == 0) &&
      rawAddress[10] == 255 &&
      rawAddress[11] == 255 &&
      rawAddress[12] == 127;
  if (isMappedIpv4Loopback) {
    return true;
  }

  final parts = host.split('.');
  if (parts.isEmpty ||
      parts.length > 4 ||
      parts.any((part) => !RegExp(r'^\d+$').hasMatch(part))) {
    return false;
  }

  final values = parts.map(int.tryParse).toList();
  if (values.any((value) => value == null)) {
    return false;
  }

  final numbers = values.cast<int>();
  switch (numbers.length) {
    case 1:
      return numbers.first == 127 ||
          (numbers.first <= 0xffffffff && numbers.first >> 24 == 127);
    case 2:
      return numbers.first == 127 &&
          numbers.first <= 0xff &&
          numbers[1] <= 0xffffff;
    case 3:
      return numbers.first == 127 &&
          numbers.first <= 0xff &&
          numbers[1] <= 0xff &&
          numbers[2] <= 0xffff;
    case 4:
      return numbers.first == 127 && numbers.every((number) => number <= 0xff);
  }

  return false;
}
