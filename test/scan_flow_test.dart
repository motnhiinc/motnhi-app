import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/data/models/image_target_manifest.dart';
import 'package:storybook_ar/data/repositories/http_session_repository.dart';
import 'package:storybook_ar/data/sources/api_client.dart';
import 'package:storybook_ar/data/sources/image_target_resolver.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/features/ar/scan_flow_controller.dart';
import 'package:storybook_ar/features/ar/simulated_page_detector.dart';

final _manifest = ImageTargetManifest(
  storyId: 'story_bunny_forest',
  version: 1,
  targets: [
    ImageTarget(
      pageId: 'page_bunny_03',
      pageNumber: 3,
      imageTargetId: 'imgt_page_bunny_03',
      physicalWidthMm: 210,
    ),
  ],
);

/// Builds a [ScanFlowController] backed by a real [HttpSessionRepository] whose
/// requests are captured by [adapter], plus a fake resolver and spy player.
Future<ScanFlowController> _controller({
  required _CapturingAdapter adapter,
  required List<String> played,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await KeyValueStore.create();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;
  final api = ApiClient(dio: dio, store: store, authDio: dio);

  return ScanFlowController(
    resolver: _FakeResolver(_manifest),
    sessionRepository: HttpSessionRepository(api),
    detectorFactory: (m) => SimulatedPageDetector(m.targets),
    childProfileId: 'p1',
    storyId: 'story_bunny_forest',
    onPlayPage: (pageId) async => played.add(pageId),
  );
}

void main() {
  test('detecting a manifest page starts a scan session and posts scan_success',
      () async {
    final adapter = _CapturingAdapter();
    final played = <String>[];
    final controller = await _controller(adapter: adapter, played: played);

    await controller.start();
    await controller.handleDetected('page_bunny_03');

    expect(played, ['page_bunny_03']);

    final sessionReq = adapter.requests
        .firstWhere((r) => r.path.endsWith('/v1/story-sessions'));
    final sessionBody = (sessionReq.data as Map).cast<String, dynamic>();
    expect(sessionBody['mode'], 'scan');
    expect(sessionBody['child_profile_id'], 'p1');
    expect(sessionBody['story_id'], 'story_bunny_forest');

    final eventReq =
        adapter.requests.firstWhere((r) => r.path.endsWith('/events'));
    final eventBody = (eventReq.data as Map).cast<String, dynamic>();
    expect(eventBody['event_type'], 'scan_success');
    expect(eventBody['page_id'], 'page_bunny_03');
  });

  test('detecting a non-manifest page posts nothing', () async {
    final adapter = _CapturingAdapter();
    final played = <String>[];
    final controller = await _controller(adapter: adapter, played: played);

    await controller.start();
    await controller.handleDetected('page_unknown');

    expect(played, isEmpty);
    expect(
      adapter.requests.where((r) => r.path.contains('/v1/story-sessions')),
      isEmpty,
    );
  });

  test('repeated detections reuse a single scan session', () async {
    final adapter = _CapturingAdapter();
    final played = <String>[];
    final controller = await _controller(adapter: adapter, played: played);

    await controller.start();
    await controller.handleDetected('page_bunny_03');
    await controller.handleDetected('page_bunny_03');

    final sessionStarts =
        adapter.requests.where((r) => r.path.endsWith('/v1/story-sessions'));
    expect(sessionStarts.length, 1);
    expect(played, ['page_bunny_03', 'page_bunny_03']);
  });
}

class _FakeResolver implements ImageTargetResolver {
  _FakeResolver(this._manifest);

  final ImageTargetManifest _manifest;

  @override
  Future<ImageTargetManifest> fetch(String storyId) async => _manifest;
}

/// A [HttpClientAdapter] that records every [RequestOptions] and returns canned
/// responses so tests can assert the posted request bodies.
class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<dynamic>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;
    if (path.endsWith('/v1/auth/device')) {
      return _json({'token': 't', 'user_id': 'u'});
    }
    if (path.endsWith('/events')) {
      return _json({'ok': true});
    }
    if (path.endsWith('/v1/story-sessions')) {
      return _json({
        'id': 'sess1',
        'child_profile_id': 'p1',
        'story_id': 'story_bunny_forest',
        'started_at': '2026-07-02T10:00:00Z',
        'completed_at': null,
        'last_page_number': 0,
        'mode': 'scan',
      });
    }
    return _json(<String, dynamic>{});
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
