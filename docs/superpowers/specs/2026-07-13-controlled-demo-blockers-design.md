# Controlled Demo Blockers Design

## Goal

Make a release-mode Android build reliably connect to the existing HTTPS VPS stack for a controlled demonstration. Preserve the current simulated scan flow, placeholder visuals, TTS fallback, and single-VPS architecture.

## Scope

- Grant release Android builds network access.
- Keep localhost convenient for debug development while requiring an explicit, valid HTTPS API URL in release mode.
- Ensure concurrent initial API requests share one device-authentication operation.
- Make onboarding recover from backend failures and allow retry.
- Validate that the existing VPS deployment assets and secret ignore rules are complete and internally consistent.

The work does not include public-traffic hardening, secure credential storage, native page recognition, production media, release signing, staging, committing, deploying, or running the app.

## Android Networking

Add `android.permission.INTERNET` to the main manifest so it is included in release builds. Keep camera and microphone declarations unchanged.

## API URL Validation

Keep `http://localhost:8000` as the debug default. Before constructing the API client in a release build, validate that `API_BASE_URL`:

- was explicitly supplied rather than using the localhost default;
- uses HTTPS;
- has a non-empty host;
- does not target localhost or a loopback address.

Invalid release configuration must fail immediately with a message that names `API_BASE_URL` and shows the required `--dart-define` form. Debug builds retain their current local-development behavior.

## Authentication Bootstrap

`ApiClient` will keep one nullable in-flight token future. When no cached token exists, the first caller starts device authentication and concurrent callers await the same future. The future is cleared in `whenComplete`, allowing a later request to retry after either success or failure.

The existing persisted device ID, device secret, token, and one-time 401 retry behavior remain unchanged.

## Onboarding Failure Recovery

Wrap consent persistence and profile creation in `try/catch/finally`:

- successful completion keeps the existing profile refresh and navigation behavior;
- failure keeps the user on onboarding and displays a concise retry message;
- `_saving` is reset in `finally` while the widget remains mounted;
- no backend exception details are shown to the user.

Consent may remain locally persisted if profile creation fails. Repeating the operation is safe because profile creation uses the existing upsert contract.

## Deployment Assets

Inspect `.dockerignore`, `backend/.gitignore`, and `backend/deploy/` for the files referenced by the deployment documentation, executable scripts, required environment values, and secret exclusions. Only concrete defects discovered during validation will be edited.

The files will remain unstaged and uncommitted.

## Verification

- Run formatting on edited Dart files.
- Run targeted static analysis for edited Dart files.
- Run short unit tests covering API authentication bootstrap and configuration validation where practical.
- Do not run `flutter run`, widget tests, integration tests, containers, migrations, or deployment commands.
- Inspect `git diff` and `git status` to confirm only scoped files changed and deployment assets remain available.

## Success Criteria

- A release APK includes Android network permission.
- A release build cannot silently target localhost or plain HTTP.
- Simultaneous first API requests result in one authentication request.
- Failed onboarding visibly recovers and can be retried.
- The existing VPS deployment package is internally consistent and protected from committing live secrets.
