// TC-05 — Duration beyond 5 seconds
// Tests DurationUtils.isClose() for the +50 bonus boundary condition.
//
// TC-05A: Verifies isClose() returns false when the candidate duration differs
//         from the query by MORE than 5 seconds (no duration bonus awarded).
// TC-05B: Confirms the boundary — exactly 5 seconds apart still returns true
//         (bonus IS awarded).
// TC-05C: Confirms a far-over-threshold difference is clearly rejected.
//
// These tests verify the negative side of the duration scoring logic in
// SourcedTrack.rankResults(): candidates outside the 5-second tolerance
// receive 0 duration bonus, which causes them to rank lower than candidates
// within tolerance — all else being equal.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/utils/duration_utils.dart';

void main() {
  group('DurationUtils.isClose', () {
    // TC-05A: Core negative case — difference > 5 s returns false (no +50 bonus)
    test(
        'TC-05A: returns false when duration difference exceeds 5 seconds '
        '(4:51 vs 5:10 = 19 s apart)', () {
      // Ride by Lana Del Rey: 4:51 = 291 s  vs  candidate: 5:10 = 310 s
      const query = Duration(seconds: 291); // 4:51
      const candidate = Duration(seconds: 310); // 5:10
      // Difference is 19 seconds, well beyond the 5-second tolerance.
      expect(DurationUtils.isClose(candidate, query), isFalse,
          reason: 'A 19-second gap must NOT award the duration bonus (+50).');
    });

    // TC-05B: Boundary case — exactly 5 s apart returns true (+50 bonus IS awarded)
    test('TC-05B: returns true when duration difference is exactly 5 seconds',
        () {
      const query = Duration(seconds: 291); // 4:51
      const candidate = Duration(seconds: 296); // 4:56
      // Exactly at the tolerance boundary — should still be considered close.
      expect(DurationUtils.isClose(candidate, query), isTrue,
          reason: 'Exactly 5 seconds apart is within tolerance; '
              'duration bonus should be awarded.');
    });

    // TC-05C: Clearly within range — 2 s apart returns true (+50 bonus)
    test('TC-05C: returns true when duration difference is within 5 seconds '
        '(2 s apart)', () {
      const query = Duration(seconds: 291); // 4:51
      const candidate = Duration(seconds: 293); // 4:53
      expect(DurationUtils.isClose(candidate, query), isTrue,
          reason:
              'A 2-second gap is within tolerance; duration bonus is awarded.');
    });

    // TC-05D: Difference of 6 s — just over the threshold, returns false
    test(
        'TC-05D: returns false when duration difference is 6 seconds '
        '(just over threshold)', () {
      const query = Duration(seconds: 291);
      const candidate = Duration(seconds: 297); // 291 + 6
      expect(DurationUtils.isClose(candidate, query), isFalse,
          reason: 'A 6-second gap exceeds the 5-second tolerance; '
              'no duration bonus should be awarded.');
    });
  });
}
