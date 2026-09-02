import 'dart:io';

import 'package:dio/dio.dart';

import '../../features/story_composer/story_draft.dart';
import '../models/models.dart';
import '../sources/api_client.dart';
import 'authored_story_repository.dart';

/// HTTP implementation backed by POST /v1/stories and DELETE /v1/stories/{id}.
class HttpAuthoredStoryRepository implements AuthoredStoryRepository {
  HttpAuthoredStoryRepository(this._api);

  final ApiClient _api;

  @override
  Future<Story> createStory(StoryDraft draft) async {
    try {
      final resp = await _api.send(
        () => _api.dio.post('/v1/stories', data: draft.toJson()),
      );
      return Story.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw AuthoredStoryFailure(_failureCode(error));
    }
  }

  @override
  Future<void> deleteStory(String storyId) async {
    try {
      await _api.send(() => _api.dio.delete('/v1/stories/$storyId'));
    } on DioException catch (error) {
      // Already gone is the outcome the caller wanted.
      if (error.response?.statusCode == 404) return;
      throw AuthoredStoryFailure(_failureCode(error));
    }
  }
}

String _failureCode(DioException error) {
  // A structured privacy-gate detail wins over the status-code mapping, so
  // creation blocked pending policy review surfaces with its real code.
  final response = error.response;
  if (response != null) {
    final detail = response.data is Map<String, dynamic>
        ? (response.data as Map<String, dynamic>)['detail']
        : null;
    if (detail == 'privacy_policy_review_required') return detail;
  }

  switch (error.response?.statusCode) {
    case 401:
    case 403:
      return 'authentication';
    case 409:
      return 'quota_reached';
    case 422:
      return 'invalid_story';
    case 429:
      return 'rate_limited';
  }

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'timeout';
    case DioExceptionType.connectionError:
      return 'backend_unreachable';
    case DioExceptionType.badCertificate:
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return 'upstream_failed';
    case DioExceptionType.unknown:
      return error.error is SocketException
          ? 'backend_unreachable'
          : 'upstream_failed';
  }
}
