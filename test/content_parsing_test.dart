// Verifies the bundled story JSON (assets/data/*.json) deserializes cleanly
// through the freezed models — the content <-> model contract (§10/§11).
// Pure file IO + parsing, no widgets, fast.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/models.dart';

void main() {
  final manifest = json.decode(
    File('assets/data/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final slugs = (manifest['stories'] as List).cast<String>();

  test('manifest lists the five demo stories', () {
    expect(slugs.length, 5);
  });

  for (final slug in slugs) {
    test('$slug parses into a valid StoryDetail', () {
      final raw = File('assets/data/$slug.json').readAsStringSync();
      final detail =
          StoryDetail.fromJson(json.decode(raw) as Map<String, dynamic>);

      expect(detail.story.slug, slug);
      expect(detail.pages, isNotEmpty);
      expect(detail.segments, isNotEmpty);

      // Every segment references a real page.
      final pageIds = detail.pages.map((p) => p.id).toSet();
      for (final seg in detail.segments) {
        expect(pageIds.contains(seg.pageId), isTrue,
            reason: 'segment ${seg.id} points at unknown page ${seg.pageId}');
        expect(seg.audioAssetId, 'aud_${seg.id}',
            reason: 'segment ${seg.id} must carry its pre-populated audio_asset_id');
      }

      // Every AR tap interaction references a real segment.
      for (final scene in detail.arScenes) {
        for (final i in scene.sceneJson.interactions) {
          if (i.action == ArAction.playAudioSegment) {
            expect(
              detail.segments.any((s) => s.id == i.audioSegmentId),
              isTrue,
              reason: 'AR interaction in ${scene.id} points at unknown '
                  'segment ${i.audioSegmentId}',
            );
          }
        }
      }

      // Every question references a real page and has exactly one correct
      // answer.
      for (final q in detail.questions) {
        expect(pageIds.contains(q.pageId), isTrue);
        expect(q.choices.where((c) => c.isCorrect).length, 1,
            reason: 'question ${q.id} must have exactly one correct choice');
      }
    });
  }

  test('Story.isAuthored defaults to false and decodes is_authored', () {
    const base = {
      'id': 's1',
      'title': 'T',
      'slug': 'authored-abc',
      'age_min': 3,
      'age_max': 8,
      'language_code': 'en',
      'duration_seconds': 60,
      'content_status': 'published',
      'themes': <String>[],
    };
    expect(Story.fromJson({...base}).isAuthored, isFalse);
    expect(Story.fromJson({...base, 'is_authored': true}).isAuthored, isTrue);
  });
}
