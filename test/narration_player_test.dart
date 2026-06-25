import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/features/player/narration_player.dart';

NarrationSegment _seg(String id, {String? audioAssetId}) => NarrationSegment(
      id: id,
      storyId: 's',
      pageId: 'p',
      speakerKey: 'narrator',
      text: 'hello',
      voiceId: 'v',
      audioAssetId: audioAssetId,
      sortOrder: 1,
    );

void main() {
  test('no fallback when every segment has a resolved URL', () {
    final segs = [_seg('a', audioAssetId: 'aud_a'), _seg('b', audioAssetId: 'aud_b')];
    final urls = {'aud_a': 'http://x/a', 'aud_b': 'http://x/b'};
    expect(NarrationPlayer.computeTtsFallback(segs, urls), isFalse);
  });

  test('fallback when a segment has an asset id but no resolved URL', () {
    final segs = [_seg('a', audioAssetId: 'aud_a'), _seg('b', audioAssetId: 'aud_b')];
    final urls = {'aud_a': 'http://x/a'}; // aud_b unresolved
    expect(NarrationPlayer.computeTtsFallback(segs, urls), isTrue);
  });

  test('fallback when a segment has no asset id at all', () {
    final segs = [_seg('a', audioAssetId: 'aud_a'), _seg('b')];
    final urls = {'aud_a': 'http://x/a'};
    expect(NarrationPlayer.computeTtsFallback(segs, urls), isTrue);
  });

  test('no fallback when segments list is empty', () {
    expect(NarrationPlayer.computeTtsFallback([], {}), isFalse);
  });

  test('fallback for an all-TTS page (no asset ids anywhere)', () {
    final segs = [_seg('a'), _seg('b')]; // neither has an audioAssetId
    expect(NarrationPlayer.computeTtsFallback(segs, {}), isTrue);
  });
}
