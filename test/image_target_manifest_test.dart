import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/image_target_manifest.dart';

void main() {
  test('ImageTargetManifest.fromJson parses the snake_case backend contract',
      () {
    final json = {
      'story_id': 'story_bunny_forest',
      'version': 1,
      'targets': [
        {
          'page_id': 'page_bunny_03',
          'page_number': 3,
          'image_target_id': 'imgt_page_bunny_03',
          'reference_image_url': null,
          'physical_width_mm': 210,
        },
        {
          'page_id': 'page_bunny_04',
          'page_number': 4,
          'image_target_id': 'imgt_page_bunny_04',
          'reference_image_url': 'https://cdn.example/page_bunny_04.png',
          'physical_width_mm': 210,
        },
      ],
    };

    final manifest = ImageTargetManifest.fromJson(json);

    expect(manifest.storyId, 'story_bunny_forest');
    expect(manifest.version, 1);
    expect(manifest.targets.length, 2);

    final first = manifest.targets.first;
    expect(first.pageId, 'page_bunny_03');
    expect(first.pageNumber, 3);
    expect(first.imageTargetId, 'imgt_page_bunny_03');
    expect(first.referenceImageUrl, isNull);
    expect(first.physicalWidthMm, 210);

    final second = manifest.targets[1];
    expect(second.referenceImageUrl, 'https://cdn.example/page_bunny_04.png');
  });

  test('ImageTargetManifest.fromJson defaults targets to empty when omitted',
      () {
    final manifest = ImageTargetManifest.fromJson({
      'story_id': 'story_bunny_forest',
      'version': 1,
    });

    expect(manifest.targets, isEmpty);
  });
}
