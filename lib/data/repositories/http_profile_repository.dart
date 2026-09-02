import 'dart:io';

import 'package:dio/dio.dart';

import '../models/models.dart';
import '../sources/api_client.dart';
import 'profile_repository.dart';

/// HTTP implementation of [ProfileRepository]. Child profiles live server-side
/// (scoped to the device user); consent lives in privacy state (§14).
class HttpProfileRepository implements ProfileRepository {
  HttpProfileRepository(this._api);

  final ApiClient _api;

  @override
  Future<ChildProfile?> getProfile() async {
    try {
      final resp = await _api.send(() => _api.dio.get('/v1/child-profiles'));
      final list = (resp.data as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return null;
      return ChildProfile.fromJson(list.first);
    } on DioException catch (error) {
      throw ProfileFailure(_failureCode(error));
    }
  }

  @override
  Future<void> saveProfile(ChildProfile profile) async {
    final body = profile.toJson()..remove('user_id'); // server sets user_id from JWT
    try {
      await _api.send(() => _api.dio.post('/v1/child-profiles', data: body));
    } on DioException catch (error) {
      throw ProfileFailure(_failureCode(error));
    }
  }
}

String _failureCode(DioException error) {
  // A structured backend detail wins, so `privacy_policy_review_required`
  // surfaces verbatim and the caller can branch on it.
  final response = error.response;
  if (response != null) {
    final detail = response.data is Map<String, dynamic>
        ? (response.data as Map<String, dynamic>)['detail']
        : null;
    if (detail is String && detail.isNotEmpty) return detail;
  }

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return 'network';
    case DioExceptionType.unknown:
      return error.error is SocketException ? 'network' : 'invalid_response';
    case DioExceptionType.badCertificate:
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return 'invalid_response';
  }
}
