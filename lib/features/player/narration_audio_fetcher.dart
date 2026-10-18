import 'dart:async';

import '../../data/models/models.dart';
import '../scan_any_page/tts_client.dart';

/// Supplies a locally cached narration clip for a segment that carries no
/// pre-generated `audio_asset_id`. Returns null when generation fails, which
/// the player reads as "fall back to on-device TTS".
abstract interface class NarrationAudioFetcher {
  Future<String?> pathFor(NarrationSegment segment);

  Future<void> dispose();
}

/// Backed by the authenticated ElevenLabs proxy (`POST /v1/tts`).
///
/// Caches the in-flight [Future], not the finished path: two requests for the
/// same segment — a page-back before the first resolves — must not both write
/// to the same file while just_audio holds it open. Failures are deliberately
/// not cached, so a dropped connection stays retryable on the next page turn.
class TtsNarrationAudioFetcher implements NarrationAudioFetcher {
  TtsNarrationAudioFetcher(this._client);

  final TtsClient _client;
  final Map<String, Future<String?>> _cache = {};

  @override
  Future<String?> pathFor(NarrationSegment segment) {
    final cached = _cache[segment.id];
    if (cached != null) return cached;

    final pending = _generate(segment);
    _cache[segment.id] = pending;
    return pending;
  }

  Future<String?> _generate(NarrationSegment segment) async {
    try {
      final file = await _client.generate(
        segment.text,
        fileName: 'narration_${segment.id}.mp3',
      );
      return file.path;
    } catch (_) {
      // Keep it retryable: a failed fetch must not poison the cache.
      _cache.remove(segment.id);
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    // dispose() deletes every generated file, so the cache must not outlive it
    // — a surviving entry would hand back a dangling path.
    _cache.clear();
    await _client.dispose();
  }
}
