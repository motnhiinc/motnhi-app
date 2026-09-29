import 'dart:io';

import 'package:dio/dio.dart';

import '../models/models.dart';
import '../sources/api_client.dart';
import 'privacy_repository.dart';

/// HTTP implementation backed by GET/PUT /v1/privacy, POST
/// /v1/privacy/activity, and DELETE /v1/privacy/{reading-history,child-data}.
/// The activity and deletion endpoints do not exist server-side yet; the
/// client-side contract is defined here first (Task 7).
class HttpPrivacyRepository implements PrivacyRepository {
  HttpPrivacyRepository(this._api);

  final ApiClient _api;

  @override
  Future<PrivacyState> fetchPrivacy() async {
    try {
      final resp = await _api.send(() => _api.dio.get('/v1/privacy'));
      return PrivacyState.fromJson(_dataMap(resp));
    } on DioException catch (error) {
      throw PrivacyFailure(_failureCode(error));
    }
  }

  @override
  Future<PrivacyState> updatePrivacy({
    required String policyVersion,
    required bool coreStorageAccepted,
    required bool progressTrackingEnabled,
    required bool cloudTtsEnabled,
    required bool pageImageValidationEnabled,
  }) async {
    try {
      final resp = await _api.send(
        () => _api.dio.put(
          '/v1/privacy',
          data: {
            'policy_version': policyVersion,
            'core_storage_accepted': coreStorageAccepted,
            'progress_tracking_enabled': progressTrackingEnabled,
            'cloud_tts_enabled': cloudTtsEnabled,
            'page_image_validation_enabled': pageImageValidationEnabled,
          },
        ),
      );
      return PrivacyState.fromJson(_dataMap(resp));
    } on DioException catch (error) {
      throw PrivacyFailure(_failureCode(error));
    }
  }

  @override
  Future<void> recordActivity() async {
    try {
      await _api.send(() => _api.dio.post('/v1/privacy/activity'));
    } on DioException catch (error) {
      throw PrivacyFailure(_failureCode(error));
    }
  }

  @override
  Future<void> deleteReadingHistory() async {
    try {
      await _api.send(() => _api.dio.delete('/v1/privacy/reading-history'));
    } on DioException catch (error) {
      throw PrivacyFailure(_failureCode(error));
    }
  }

  @override
  Future<void> deleteChildData() async {
    try {
      await _api.send(() => _api.dio.delete('/v1/privacy/child-data'));
    } on DioException catch (error) {
      throw PrivacyFailure(_failureCode(error));
    }
  }

  /// 204 responses carry no body; only fetch/update are parsed, and a body
  /// that is not an object is malformed.
  Map<String, dynamic> _dataMap(Response<dynamic> resp) {
    final data = resp.data;
    if (data is Map<String, dynamic>) return data;
    throw PrivacyFailure('invalid_response');
  }
}

String _failureCode(DioException error) {
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
