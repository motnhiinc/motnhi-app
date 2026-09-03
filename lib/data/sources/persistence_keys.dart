/// Authoritative registry of every SharedPreferences key the app persists
/// (Task 19). Key literals must never be hardcoded at call sites — always
/// reference these constants so the key set stays auditable.
///
/// Key ownership:
/// - [preservedKeys] survive child-data deletion (device identity, auth
///   credentials, UI locale choice).
/// - `childDataKeys` are child-derived data the local cleaner (Task 20) may
///   remove on parent request.
/// - [childCleanupPendingKey] is the ordered-cleanup repair marker (Task 20).
///
/// Legacy keys no longer written (e.g. [parentConsentKey]) are kept in the
/// registry so deletion still clears them on old installations.
library;

/// Anonymous device identifier persisted on first registration.
const deviceIdKey = 'device_id';

/// Server-issued device secret (proof-of-possession). Never cleared locally.
const deviceSecretKey = 'device_secret';

/// Server user id returned by /v1/auth/device.
const authUserIdKey = 'auth_user_id';

/// Cached JWT access token. Cleared on 401 to force re-minting.
const authTokenKey = 'auth_token';

/// UI-language override chosen in Settings (null = follow system locale).
const uiLocaleOverrideKey = 'ui_locale_override';

/// Legacy local parent-consent record; consent lives server-side now (§14).
/// Retained so old installations can be cleaned.
const parentConsentKey = 'parent_consent';

/// Persisted child profile JSON (§9.5.2, §7.2.1).
const childProfileKey = 'child_profile';

/// Persisted story-session history JSON list (§9.5.6).
const storySessionsKey = 'story_sessions';

/// Persisted telemetry events JSON list (§9.5.6, §11.4).
const interactionEventsKey = 'interaction_events';

/// Persisted parent reading-settings JSON (§7.2.4).
const readingSettingsKey = 'reading_settings';

/// Daily reading-time ceiling in minutes, stored as a string.
const settingsDailyLimitMinutesKey = 'settings_daily_limit_minutes';

/// Content-filter age band name.
const settingsContentFilterBandKey = 'settings_content_filter_band';

/// Learning-report notifications opt-in.
const settingsNotificationsEnabledKey = 'settings_notifications_enabled';

/// Persisted AR character selection.
const arSelectedCharacterIdKey = 'ar.selected_character_id';

/// Display-only cache of the last server privacy response. Never consulted
/// for authorization (§14).
const privacyStateCacheKey = 'privacy_state_cache';

/// Local throttle key recording the last recorded activity instant.
const privacyActivityLastUtcDateKey = 'privacy_activity_last_utc_date';

/// Ordered-cleanup marker set before local child-data deletion and cleared
/// after it (Task 20 repair bootstrap).
const childCleanupPendingKey = 'child_cleanup_pending';

/// Keys that survive child-data deletion: device identity + auth credentials
/// + UI locale choice.
const preservedKeys = <String>{
  deviceIdKey,
  deviceSecretKey,
  authUserIdKey,
  authTokenKey,
  uiLocaleOverrideKey,
};

/// Child-derived data keys the local cleaner may remove on parent request.
const childDataKeys = <String>{
  parentConsentKey,
  childProfileKey,
  storySessionsKey,
  interactionEventsKey,
  readingSettingsKey,
  settingsDailyLimitMinutesKey,
  settingsContentFilterBandKey,
  settingsNotificationsEnabledKey,
  arSelectedCharacterIdKey,
  privacyStateCacheKey,
  privacyActivityLastUtcDateKey,
};

/// The single cleanup-repair marker key.
const String cleanupPendingKey = childCleanupPendingKey;

/// Every persisted key the app can ever touch. Exhaustive by contract; the
/// registry test asserts completeness and disjointness of the groups.
const allKnownKeys = <String>{
  ...preservedKeys,
  ...childDataKeys,
  childCleanupPendingKey
};
