import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/image_target_manifest.dart';
import 'package:storybook_ar/features/ar/simulated_page_detector.dart';

ImageTarget _target(String pageId, int pageNumber) => ImageTarget(
      pageId: pageId,
      pageNumber: pageNumber,
      imageTargetId: 'imgt_$pageId',
      physicalWidthMm: 210,
    );

void main() {
  test('simulateDetection emits manifest page ids through the seam', () {
    final detector =
        SimulatedPageDetector([_target('page_a', 1), _target('page_b', 2)]);
    final emitted = <String>[];
    detector.onDetected = emitted.add;

    detector.simulateDetection('page_a');
    detector.simulateDetection('page_b');

    expect(emitted, ['page_a', 'page_b']);
  });

  test('a page id not in the manifest is a no-op', () {
    final detector = SimulatedPageDetector([_target('page_a', 1)]);
    final emitted = <String>[];
    detector.onDetected = emitted.add;

    detector.simulateDetection('page_missing');

    expect(emitted, isEmpty);
  });

  test('fromManifest exposes the manifest page ids', () {
    final detector = SimulatedPageDetector.fromManifest(
      ImageTargetManifest(
        storyId: 'story_bunny_forest',
        version: 1,
        targets: [_target('page_a', 1), _target('page_b', 2)],
      ),
    );

    expect(detector.pageIds, ['page_a', 'page_b']);
  });
}
