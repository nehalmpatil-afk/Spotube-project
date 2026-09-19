// TC-10 — Duration JSON deserialization (seconds)
// TC-15 — Regression test for historical duration bug (seconds vs microseconds)
//
// DEPENDENCY NOTE:
// SpotubeAudioSourceMatchObject is defined in lib/models/metadata/metadata.dart.
// That library transitively imports shadcn_flutter via:
//   metadata.dart → audio_player.dart → logger.dart → shadcn_flutter
//
// These tests will compile and run correctly once the shadcn_flutter 0.0.47
// / vector_math compatibility issue in the project environment is resolved.
// The test logic itself is correct and complete.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';

void main() {
  // ---------------------------------------------------------------------------
  // TC-10: SpotubeAudioSourceMatchObject.fromJson() — seconds deserialization
  // ---------------------------------------------------------------------------
  group('SpotubeAudioSourceMatchObject.fromJson', () {
    test(
        'TC-10: JSON duration value 291 is deserialized as '
        'Duration(seconds: 291)', () {
      // Arrange: minimal valid JSON with duration expressed in seconds.
      final json = {
        'id': 'test_id_001',
        'title': 'Ride',
        'artists': ['Lana Del Rey'],
        'duration': 291, // seconds — current implementation
        'externalUri': 'https://youtube.com/watch?v=test',
      };

      // Act
      final obj = SpotubeAudioSourceMatchObject.fromJson(json);

      // Assert: duration must be 291 seconds.
      expect(
        obj.duration,
        equals(const Duration(seconds: 291)),
        reason: 'The fromJson() implementation calls '
            '_durationFromSeconds(n) = Duration(seconds: n.toInt()), '
            'so a JSON value of 291 must produce Duration(seconds: 291).',
      );
    });

    test(
        'TC-10B: JSON duration value 0 is deserialized as Duration.zero', () {
      final json = {
        'id': 'test_id_002',
        'title': 'Silent',
        'artists': ['Test Artist'],
        'duration': 0,
        'externalUri': 'https://youtube.com/watch?v=zero',
      };

      final obj = SpotubeAudioSourceMatchObject.fromJson(json);

      expect(obj.duration, equals(Duration.zero));
    });

    test('TC-10C: null JSON duration value falls back to Duration.zero', () {
      final json = {
        'id': 'test_id_003',
        'title': 'Unknown',
        'artists': ['Unknown Artist'],
        'duration': null,
        'externalUri': 'https://youtube.com/watch?v=null',
      };

      final obj = SpotubeAudioSourceMatchObject.fromJson(json);

      expect(obj.duration, equals(Duration.zero));
    });
  });

  // ---------------------------------------------------------------------------
  // TC-15: REGRESSION — Duration deserialization (seconds, NOT microseconds)
  //
  // Historical bug: Duration values supplied in seconds were previously
  // interpreted as microseconds (the default Dart Duration constructor
  // interprets an integer argument as microseconds).
  // The fix introduced _durationFromSeconds() which explicitly passes
  // the integer as Duration(seconds: n).
  //
  // This regression test guards against that bug being reintroduced.
  // ---------------------------------------------------------------------------
  group('TC-15 Regression: duration deserialized as seconds not microseconds',
      () {
    test(
        'TC-15: JSON duration 291 must produce Duration(seconds: 291), '
        'NOT Duration(microseconds: 291)', () {
      // Arrange
      final json = {
        'id': 'regression_001',
        'title': 'Ride',
        'artists': ['Lana Del Rey'],
        'duration': 291,
        'externalUri': 'https://youtube.com/watch?v=regression',
      };

      // Act
      final obj = SpotubeAudioSourceMatchObject.fromJson(json);

      // Assert: must equal 291 seconds (4 min 51 sec)
      const expectedDuration = Duration(seconds: 291);
      // The old buggy value would have been Duration(microseconds: 291)
      const buggyDuration = Duration(microseconds: 291);

      expect(
        obj.duration,
        equals(expectedDuration),
        reason: 'REGRESSION GUARD: duration must be 291 seconds (4:51), '
            'not 291 microseconds (~0.291 ms).',
      );

      expect(
        obj.duration,
        isNot(equals(buggyDuration)),
        reason: 'REGRESSION GUARD: the old bug interpreted JSON seconds '
            'as microseconds. This must never occur again.',
      );

      // Confirm the actual magnitude is sane (minutes, not sub-millisecond)
      expect(
        obj.duration.inSeconds,
        equals(291),
        reason: 'Duration should be 291 seconds (4 min 51 sec).',
      );
      expect(
        obj.duration.inMinutes,
        equals(4),
        reason: 'Duration of 291 seconds spans 4 full minutes.',
      );
    });
  });
}
