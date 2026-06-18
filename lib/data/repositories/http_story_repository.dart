import 'package:dio/dio.dart';

import '../models/models.dart';
import '../sources/api_client.dart';
import 'story_repository.dart';

/// HTTP implementation of [StoryRepository] backed by GET /v1/stories
/// (spec §11.1) and GET /v1/stories/{id} (§11.2).
class HttpStoryRepository implements StoryRepository {
  HttpStoryRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Story>> getLibrary({AgeBand? ageBand, String? language}) async {
    final resp = await _api.send(() => _api.dio.get('/v1/stories', queryParameters: {
      'age_band': ?ageBand?.label,
      'language': ?language,
    }));
    final list = (resp.data['stories'] as List).cast<Map<String, dynamic>>();
    return list.map(Story.fromJson).toList();
  }

  @override
  Future<StoryDetail?> getStory(String storyId) async {
    try {
      final resp = await _api.send(() => _api.dio.get('/v1/stories/$storyId'));
      return StoryDetail.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
