import 'dart:io';

import '../scan_any_page/tts_client.dart';

/// Selects the Scan Any Page narration source for one operation (§14):
/// device-only when effective cloud-narration consent is false, and a
/// cloud-first wrapper when true.
TtsClient selectNarrationSource({
  required bool cloudNarrationEnabled,
  required TtsClient cloudClient,
  required TtsClient deviceClient,
}) {
  if (!cloudNarrationEnabled) return deviceClient;
  return CloudFirstTtsClient(cloud: cloudClient, device: deviceClient);
}

/// Tries the cloud client first and falls back to the device on any cloud
/// generation failure (consent, network, upstream, invalid audio). Input
/// validation failures before generation (`invalid_text`, per [TtsClient]
/// conventions) propagate — there is nothing a device retry can fix there.
final class CloudFirstTtsClient implements TtsClient {
  CloudFirstTtsClient({
    required TtsClient cloud,
    required TtsClient device,
  })  : _cloud = cloud,
        _device = device;

  final TtsClient _cloud;
  final TtsClient _device;

  @override
  Future<File> generate(String confirmedText, {String? fileName}) async {
    try {
      return await _cloud.generate(confirmedText, fileName: fileName);
    } on TtsGenerationFailure catch (failure) {
      if (failure.code == 'invalid_text') rethrow;
      return _device.generate(confirmedText, fileName: fileName);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _cloud.dispose();
    } finally {
      await _device.dispose();
    }
  }
}
