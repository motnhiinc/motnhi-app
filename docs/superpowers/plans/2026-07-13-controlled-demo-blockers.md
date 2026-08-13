# Controlled Demo Blockers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a release Android build reliably connect to the existing HTTPS VPS stack and recover from first-run authentication or onboarding failures during a controlled demo.

**Architecture:** Keep the current HTTP repository graph and VPS topology. Add a small testable API URL resolver at the DI boundary, serialize device token bootstrap inside `ApiClient`, and contain onboarding failures in the existing screen state. Validate deployment assets without changing them unless a concrete defect is found.

**Tech Stack:** Flutter/Dart, Riverpod, Dio, SharedPreferences, Android manifest, Flutter unit tests, Docker Compose/Caddy configuration.

---

## File Structure

- Create `lib/core/api_config.dart`: resolve and validate the compile-time API URL before Dio construction.
- Create `test/api_config_test.dart`: unit coverage for debug defaults and release URL rejection/acceptance.
- Modify `lib/core/di.dart`: consume the validated API URL.
- Modify `lib/data/sources/api_client.dart`: share one in-flight token bootstrap operation.
- Modify `test/http_repositories_test.dart`: prove concurrent requests trigger one auth request and failed bootstrap can retry.
- Modify `lib/features/onboarding/onboarding_screen.dart`: recover visibly from profile-save failures.
- Modify `android/app/src/main/AndroidManifest.xml`: grant release builds internet access.
- Validate `.dockerignore`, `backend/.gitignore`, and `backend/deploy/*`; edit only if validation finds a concrete defect.

### Task 1: Release API Configuration

**Files:**
- Create: `lib/core/api_config.dart`
- Create: `test/api_config_test.dart`
- Modify: `lib/core/di.dart:20-39`

- [ ] **Step 1: Write API configuration tests**

Add tests that call a pure resolver with an explicit `isRelease` argument:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/core/api_config.dart';

void main() {
  test('debug keeps the localhost default', () {
    expect(resolveApiBaseUrl(isRelease: false), 'http://localhost:8000');
  });

  test('release accepts an explicit HTTPS endpoint', () {
    expect(
      resolveApiBaseUrl(
        configuredUrl: 'https://api.example.com',
        isRelease: true,
      ),
      'https://api.example.com',
    );
  });

  for (final url in [
    '',
    'http://api.example.com',
    'https://localhost:8000',
    'https://127.0.0.1:8000',
    'https://[::1]:8000',
  ]) {
    test('release rejects unsafe endpoint: $url', () {
      expect(
        () => resolveApiBaseUrl(configuredUrl: url, isRelease: true),
        throwsA(isA<StateError>()),
      );
    });
  }
}
```

- [ ] **Step 2: Run the new test and verify it fails**

Run: `flutter test test/api_config_test.dart`

Expected: FAIL because `lib/core/api_config.dart` does not exist.

- [ ] **Step 3: Implement the resolver**

Create `lib/core/api_config.dart` with a debug default and release-only validation:

```dart
import 'package:flutter/foundation.dart';

const _defaultApiBaseUrl = 'http://localhost:8000';

String resolveApiBaseUrl({
  String configuredUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultApiBaseUrl,
  ),
  bool isRelease = kReleaseMode,
}) {
  if (!isRelease) return configuredUrl;

  final uri = Uri.tryParse(configuredUrl);
  final host = uri?.host.toLowerCase();
  final isLoopback = host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1';
  if (uri == null ||
      uri.scheme != 'https' ||
      host == null ||
      host.isEmpty ||
      isLoopback) {
    throw StateError(
      'Release builds require an HTTPS API_BASE_URL. Build with '
      '--dart-define=API_BASE_URL=https://api.example.com',
    );
  }
  return configuredUrl;
}
```

Replace `_apiBaseUrl` in `lib/core/di.dart` with an import of `api_config.dart` and construct Dio using:

```dart
dio: Dio(BaseOptions(baseUrl: resolveApiBaseUrl())),
```

- [ ] **Step 4: Run configuration tests**

Run: `flutter test test/api_config_test.dart`

Expected: all tests PASS.

### Task 2: Single-Flight Device Authentication

**Files:**
- Modify: `lib/data/sources/api_client.dart:47-84`
- Modify: `test/http_repositories_test.dart:28-119`

- [ ] **Step 1: Write the concurrent bootstrap test**

Add a test with separate API and authentication Dio adapters. Count authentication calls, delay the auth response, issue two API requests concurrently, and assert one auth call:

```dart
test('concurrent first requests share one device authentication', () async {
  SharedPreferences.setMockInitialValues({});
  final store = await KeyValueStore.create();
  var authCallCount = 0;

  final authDio = Dio(BaseOptions(baseUrl: 'http://test'));
  authDio.httpClientAdapter = _AsyncAdapter(
    onFetch: (options) async {
      authCallCount++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return _jsonResponse(200, {
        'token': 'shared-token',
        'user_id': 'u1',
        'device_secret': 'secret',
      });
    },
  );

  final apiDio = Dio(BaseOptions(baseUrl: 'http://test'));
  apiDio.httpClientAdapter = _AsyncAdapter(
    onFetch: (_) async => _jsonResponse(200, {'stories': []}),
  );

  final api = ApiClient(dio: apiDio, store: store, authDio: authDio);
  await Future.wait([
    api.dio.get('/v1/stories'),
    api.dio.get('/v1/child-profiles'),
  ]);

  expect(authCallCount, 1);
});
```

Add `_AsyncAdapter` and `_jsonResponse` test helpers matching Dio's existing `HttpClientAdapter` contract.

- [ ] **Step 2: Run the concurrent test and verify it fails**

Run: `flutter test test/http_repositories_test.dart --plain-name 'concurrent first requests share one device authentication'`

Expected: FAIL because the auth adapter receives two calls.

- [ ] **Step 3: Implement shared token bootstrap**

Add an in-flight future and split the existing operation:

```dart
Future<String>? _tokenBootstrap;

Future<String> _ensureToken() async {
  final cached = _store.getString(_tokenKey);
  if (cached != null) return cached;

  final inFlight = _tokenBootstrap;
  if (inFlight != null) return inFlight;

  final bootstrap = _bootstrapToken();
  _tokenBootstrap = bootstrap;
  try {
    return await bootstrap;
  } finally {
    if (identical(_tokenBootstrap, bootstrap)) {
      _tokenBootstrap = null;
    }
  }
}

Future<String> _bootstrapToken() async {
  final secret = _store.getString(_secretKey);
  final body = <String, dynamic>{'device_id': await _deviceId()};
  if (secret != null) body['device_secret'] = secret;

  final resp = await _authDio.post('/v1/auth/device', data: body);
  final token = resp.data['token'] as String;
  await _store.setString(_tokenKey, token);
  await _store.setString(_userKey, resp.data['user_id'] as String);

  final returnedSecret = resp.data['device_secret'];
  if (returnedSecret != null) {
    await _store.setString(_secretKey, returnedSecret as String);
  }
  return token;
}
```

- [ ] **Step 4: Add retry-after-failure coverage**

Add a test where the first auth adapter invocation returns HTTP 500 and the second succeeds. Assert the first API request throws, the next request succeeds, and `authCallCount == 2`. This proves the in-flight future is cleared after failure.

- [ ] **Step 5: Run API client tests**

Run: `flutter test test/http_repositories_test.dart`

Expected: all tests PASS.

### Task 3: Recoverable Onboarding

**Files:**
- Modify: `lib/features/onboarding/onboarding_screen.dart:36-52`

- [ ] **Step 1: Add guarded save behavior**

Keep the existing operation order and profile payload, but catch failures and always restore the button state:

```dart
Future<void> _finish() async {
  setState(() => _saving = true);
  try {
    final profileRepo = ref.read(profileRepositoryProvider);
    await profileRepo.setConsented(true);
    await ref.read(childProfileProvider.notifier).save(
          ChildProfile(
            id: const Uuid().v4(),
            nickname:
                _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
            ageBand: _ageBand,
            languageCode: _language,
            arEnabled: _arEnabled,
            microphoneEnabled: _microphoneEnabled,
          ),
        );
    if (mounted) context.go(AppRoutes.home);
  } catch (_) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not finish setup. Check your connection and try again.'),
        ),
      );
    }
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}
```

- [ ] **Step 2: Format and statically analyze the screen**

Run: `dart format lib/features/onboarding/onboarding_screen.dart`

Run: `flutter analyze lib/features/onboarding/onboarding_screen.dart`

Expected: both commands exit successfully with no analyzer errors.

### Task 4: Release Android Internet Permission

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml:1-8`

- [ ] **Step 1: Add the permission to the shared manifest**

Insert before camera permission:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Do not alter camera, microphone, feature, activity, or application declarations.

- [ ] **Step 2: Verify manifest placement**

Read `android/app/src/main/AndroidManifest.xml` and confirm `INTERNET` is a direct child of `<manifest>` and appears before `<application>`.

### Task 5: Deployment Package Validation

**Files:**
- Validate: `.dockerignore`
- Validate: `backend/.gitignore`
- Validate: `backend/deploy/.env.production.example`
- Validate: `backend/deploy/Caddyfile`
- Validate: `backend/deploy/Dockerfile`
- Validate: `backend/deploy/deploy.sh`
- Validate: `backend/deploy/docker-compose.prod.yml`
- Validate: `backend/deploy/entrypoint.sh`
- Validate: `backend/deploy/README.md`

- [ ] **Step 1: Validate shell syntax**

Run: `bash -n backend/deploy/deploy.sh backend/deploy/entrypoint.sh`

Expected: exit code 0 with no output.

- [ ] **Step 2: Validate Compose interpolation and structure without starting services**

Run from `backend/deploy`: `docker compose --env-file .env.production.example -f docker-compose.prod.yml config`

Expected: Compose renders the three services and named volumes. If Docker Compose is unavailable, record this validation as not run rather than installing anything.

- [ ] **Step 3: Confirm secret exclusions and required assets**

Verify:

- `.dockerignore` excludes every literal `.env` while retaining `.env.production.example`.
- `backend/.gitignore` excludes `backend/.env` and `backend/deploy/.env` relative to its own directory.
- `backend/deploy/README.md` references files that exist.
- The Compose build context and Dockerfile path resolve from `backend/deploy`.
- `deploy.sh` and `entrypoint.sh` remain executable.

Only edit a file if one of these checks exposes a concrete defect.

### Task 6: Final Verification

**Files:**
- Verify all files changed by Tasks 1-5.

- [ ] **Step 1: Format edited Dart files**

Run: `dart format lib/core/api_config.dart lib/core/di.dart lib/data/sources/api_client.dart lib/features/onboarding/onboarding_screen.dart test/api_config_test.dart test/http_repositories_test.dart`

Expected: command exits successfully.

- [ ] **Step 2: Run targeted static analysis**

Run: `flutter analyze lib/core/api_config.dart lib/core/di.dart lib/data/sources/api_client.dart lib/features/onboarding/onboarding_screen.dart test/api_config_test.dart test/http_repositories_test.dart`

Expected: no analyzer errors.

- [ ] **Step 3: Run short unit tests**

Run: `flutter test test/api_config_test.dart test/http_repositories_test.dart`

Expected: all tests PASS. These are unit tests, not widget, integration, or end-to-end tests.

- [ ] **Step 4: Inspect worktree changes**

Run: `git status --short` and `git diff -- android/app/src/main/AndroidManifest.xml lib/core/api_config.dart lib/core/di.dart lib/data/sources/api_client.dart lib/features/onboarding/onboarding_screen.dart test/api_config_test.dart test/http_repositories_test.dart docs/superpowers/specs/2026-07-13-controlled-demo-blockers-design.md docs/superpowers/plans/2026-07-13-controlled-demo-blockers.md`

Expected: only scoped changes from this work plus pre-existing unrelated worktree changes. Do not stage, commit, revert, or modify unrelated files.

## Commit Policy

No commit steps are included because the approved design explicitly keeps all changes unstaged and uncommitted.
