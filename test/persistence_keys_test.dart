import 'package:storybook_ar/data/sources/persistence_keys.dart';

import 'package:flutter_test/flutter_test.dart';

/// Registry completeness (Task 19): every persisted key the app can ever
/// touch is declared here. The three groups are pairwise disjoint:
/// preserved credentials/locale survive child-data deletion; everything else
/// is child data the local cleaner (Task 20) may remove.
void main() {
  const preservedKeys = {
    'device_id',
    'device_secret',
    'auth_user_id',
    'auth_token',
    'ui_locale_override',
  };

  const childDataKeys = {
    'parent_consent',
    'child_profile',
    'story_sessions',
    'interaction_events',
    'reading_settings',
    'settings_daily_limit_minutes',
    'settings_content_filter_band',
    'settings_notifications_enabled',
    'settings_auto_advance_pages',
    'ar.selected_character_id',
    'privacy_state_cache',
    'privacy_activity_last_utc_date',
  };

  const cleanupPendingKey = 'child_cleanup_pending';

  test('allKnownKeys is exactly preserved ∪ childData ∪ cleanupPending', () {
    final expected = <String>{
      ...preservedKeys,
      ...childDataKeys,
      cleanupPendingKey,
    };
    expect(allKnownKeys, equals(expected));
    expect(allKnownKeys.length, equals(expected.length));
  });

  test('preserved and child-data key sets are pairwise disjoint', () {
    expect(preservedKeys.intersection(childDataKeys), isEmpty);
    expect(preservedKeys, isNot(contains(cleanupPendingKey)));
    expect(childDataKeys, isNot(contains(cleanupPendingKey)));
  });

  test('registry constants map to the exact expected key strings', () {
    expect(deviceIdKey, 'device_id');
    expect(deviceSecretKey, 'device_secret');
    expect(authUserIdKey, 'auth_user_id');
    expect(authTokenKey, 'auth_token');
    expect(uiLocaleOverrideKey, 'ui_locale_override');

    expect(parentConsentKey, 'parent_consent');
    expect(childProfileKey, 'child_profile');
    expect(storySessionsKey, 'story_sessions');
    expect(interactionEventsKey, 'interaction_events');
    expect(readingSettingsKey, 'reading_settings');
    expect(settingsDailyLimitMinutesKey, 'settings_daily_limit_minutes');
    expect(settingsContentFilterBandKey, 'settings_content_filter_band');
    expect(settingsNotificationsEnabledKey, 'settings_notifications_enabled');
    expect(settingsAutoAdvancePagesKey, 'settings_auto_advance_pages');
    expect(arSelectedCharacterIdKey, 'ar.selected_character_id');
    expect(privacyStateCacheKey, 'privacy_state_cache');
    expect(privacyActivityLastUtcDateKey, 'privacy_activity_last_utc_date');
    expect(childCleanupPendingKey, 'child_cleanup_pending');
  });
}
