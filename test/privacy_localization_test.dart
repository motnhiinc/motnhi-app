import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Task 9 (§14): the privacy & consent copy must be complete in both locales
/// and must never claim that profile or progress data lives only on this
/// device — profile storage and (optional) progress tracking are cloud-side.
void main() {
  final enArb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
      as Map<String, dynamic>;
  final viArb = jsonDecode(File('lib/l10n/app_vi.arb').readAsStringSync())
      as Map<String, dynamic>;

  Map<String, String> strings(Map<String, dynamic> arb) => {
        for (final entry in arb.entries)
          if (!entry.key.startsWith('@') && entry.value is String)
            entry.key: entry.value as String,
      };

  final en = strings(enArb);
  final vi = strings(viArb);

  final sections = <String, List<String>>{
    'required storage': [
      'privacyStorageRequiredTitle',
      'privacyStorageRequiredBody',
    ],
    'optional tracking': [
      'privacyTrackingTitle',
      'privacyTrackingBody',
    ],
    'OpenAI/cloud narration': [
      'privacyCloudTitle',
      'privacyCloudBody',
    ],
    'retention': [
      'privacyRetentionTitle',
      'privacyRetentionBody',
    ],
    'deletion': [
      'privacyDeletionTitle',
      'privacyDeletionBody',
    ],
    'retry': [
      'privacySaveError',
      'profileSaveError',
      'privacyDeleteFailed',
    ],
    'policy review': [
      'privacyReviewTitle',
      'privacyReviewIntro',
      'privacyReviewContinue',
      'privacyReviewAcceptNote',
      'privacyNoticeCta',
      'privacyDeleteDataButton',
      'privacyDeleteConfirmTitle',
      'privacyDeleteConfirmBody',
    ],
    'complete notice': [
      'privacyNoticeTitle',
      'privacyNoticeIntro',
      'privacyStoredTitle',
      'privacyCameraTitle',
      'privacyCameraBody',
      'privacyDeviceIdentityTitle',
      'privacyDeviceIdentityBody',
    ],
  };

  group('privacy & consent localization (Task 9)', () {
    test('every new section has matching, non-empty keys in EN and VI', () {
      sections.forEach((section, keys) {
        for (final key in keys) {
          expect(en[key], isNotNull, reason: 'EN missing "$section" key $key');
          expect(en[key], isNotEmpty, reason: 'EN empty "$section" key $key');
          expect(vi[key], isNotNull, reason: 'VI missing "$section" key $key');
          expect(vi[key], isNotEmpty, reason: 'VI empty "$section" key $key');
        }
      });
    });

    test('no source string claims profile or progress data is device-only', () {
      for (final entry in en.entries) {
        expect(entry.value.contains('stored only on this device'), isFalse,
            reason: '${entry.key} claims device-only storage');
        expect(entry.value.contains('on this device only'), isFalse,
            reason: '${entry.key} claims device-only storage');
      }
      for (final entry in vi.entries) {
        expect(entry.value.contains('chỉ được lưu trên thiết bị'), isFalse,
            reason: '${entry.key} claims device-only storage');
      }
    });

    test('nickname remains optional in child profile settings', () {
      expect(
        en['nicknameLabel']!.toLowerCase(),
        contains('nickname or first name'),
      );
      expect(
        vi['nicknameLabel']!.toLowerCase(),
        contains('biệt danh hoặc tên gọi'),
      );
      for (final key in [
        'onboardingDefaultAge',
        'onboardingStorageTitle',
        'onboardingStorageBody',
        'childProfileTitle',
        'childProfileAgeHelp',
        'childProfileSave',
        'childProfileSaveError',
      ]) {
        expect(en[key], isNotEmpty);
        expect(vi[key], isNotEmpty);
      }
    });

    test('onboarding copy does not claim a real name is technically impossible',
        () {
      const onboardingKeys = [
        'onboardingIntro',
        'onboardingStorageBody',
        'nicknameLabel',
        'nicknameHint',
        'consentTitle',
        'consentBody',
        'privacyStorageRequiredBody',
      ];
      const forbidden = [
        'impossible',
        'cannot technically',
        'bất khả',
        'không thể',
      ];
      for (final key in onboardingKeys) {
        for (final (locale, value) in [
          ('EN', en[key]!),
          ('VI', vi[key]!),
        ]) {
          for (final phrase in forbidden) {
            expect(value.toLowerCase().contains(phrase), isFalse,
                reason: '$locale $key contains "$phrase"');
          }
        }
      }
    });

    test(
        'required-storage copy names profile fields and saved story text, '
        'and states what is not required', () {
      final enBody = en['privacyStorageRequiredBody']!.toLowerCase();
      for (final phrase in [
        'nickname or first name',
        'age range',
        'story language',
        'story title',
        'page text',
      ]) {
        expect(enBody, contains(phrase),
            reason: 'EN required-storage copy must name "$phrase"');
      }
      expect(enBody, contains('never require'));
      for (final phrase in [
        'real name',
        'birthday',
        'photo',
        'voice recording',
        'camera images',
      ]) {
        expect(enBody, contains(phrase),
            reason: 'EN required-storage copy must list "$phrase"');
      }

      final viBody = vi['privacyStorageRequiredBody']!.toLowerCase();
      for (final phrase in [
        'biệt danh hoặc tên gọi',
        'độ tuổi',
        'ngôn ngữ',
        'tên truyện',
        'nội dung trang',
      ]) {
        expect(viBody, contains(phrase),
            reason: 'VI required-storage copy must name "$phrase"');
      }
      expect(viBody, contains('không bao giờ yêu cầu'));
      for (final phrase in [
        'tên thật',
        'ngày sinh',
        'ảnh',
        'giọng nói',
        'máy ảnh',
      ]) {
        expect(viBody, contains(phrase),
            reason: 'VI required-storage copy must list "$phrase"');
      }
    });

    test('cloud narration copy describes the approved-page OpenAI path', () {
      final enBody = en['privacyCloudBody']!;
      expect(enBody, contains('OpenAI'));
      expect(enBody.toLowerCase(), contains('app backend'));
      expect(enBody.toLowerCase(), contains('approved page text'));
      expect(enBody.toLowerCase(), contains('separately enabled'));

      final viBody = vi['privacyCloudBody']!;
      expect(viBody, contains('OpenAI'));
      expect(viBody, contains('máy chủ ứng dụng'));
      expect(viBody, contains('đã được duyệt'));
      expect(viBody, contains('bật riêng'));
    });
  });
}
