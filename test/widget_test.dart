// Smoke test for the data models. Widget/integration tests for the player and
// AR flows are deferred (require audio/AR plugin platform channels).
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/models.dart';

void main() {
  test('Story.matchesAgeBand respects the age range', () {
    const story = Story(
      id: 's1',
      title: 'Test',
      slug: 'test',
      ageMin: 3,
      ageMax: 5,
    );
    expect(story.matchesAgeBand(AgeBand.threeToFour), isTrue);
    expect(story.matchesAgeBand(AgeBand.sevenToEight), isFalse);
  });

  test('StoryDetail orders pages and segments', () {
    const story = Story(id: 's1', title: 'T', slug: 't');
    final detail = StoryDetail(
      story: story,
      pages: const [
        StoryPage(id: 'p2', storyId: 's1', pageNumber: 2),
        StoryPage(id: 'p1', storyId: 's1', pageNumber: 1),
      ],
      segments: const [
        NarrationSegment(
          id: 'b',
          storyId: 's1',
          pageId: 'p1',
          speakerKey: 'narrator',
          text: 'second',
          voiceId: 'v',
          sortOrder: 2,
        ),
        NarrationSegment(
          id: 'a',
          storyId: 's1',
          pageId: 'p1',
          speakerKey: 'narrator',
          text: 'first',
          voiceId: 'v',
          sortOrder: 1,
        ),
      ],
    );
    expect(detail.orderedPages.first.pageNumber, 1);
    expect(detail.segmentsForPage('p1').first.text, 'first');
  });
}
