import 'package:ew_brother_ew/core/logical_day.dart';
import 'package:ew_brother_ew/domain/score.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogicalDay (4 AM reset)', () {
    test('2 AM belongs to the previous day', () {
      expect(LogicalDay.keyFor(DateTime(2026, 11, 2, 2, 30), 4), '2026-11-01');
    });
    test('4 AM starts the new day', () {
      expect(LogicalDay.keyFor(DateTime(2026, 11, 2, 4, 0), 4), '2026-11-02');
    });
    test('midnight reset is a plain calendar day', () {
      expect(LogicalDay.keyFor(DateTime(2026, 11, 2, 0, 1), 0), '2026-11-02');
    });
    test('minusDays crosses months', () {
      expect(LogicalDay.minusDays('2026-03-01', 1), '2026-02-28');
    });
    test('lastDays is oldest first and ends today', () {
      final d = LogicalDay.lastDays('2026-11-01', 7);
      expect(d.length, 7);
      expect(d.first, '2026-10-26');
      expect(d.last, '2026-11-01');
    });
  });

  group('dailyScore', () {
    test('perfect day', () {
      expect(
        dailyScore(habitsDone: 3, habitsTotal: 3, topDone: 3, topTotal: 3, reels: 0, limit: 100),
        100,
      );
    });
    test('no habits or tasks: reels alone decide', () {
      expect(dailyScore(habitsDone: 0, habitsTotal: 0, topDone: 0, topTotal: 0, reels: 50, limit: 100), 50);
    });
    test('reels over the limit give zero for that part', () {
      expect(dailyScore(habitsDone: 0, habitsTotal: 0, topDone: 0, topTotal: 0, reels: 300, limit: 100), 0);
    });
  });

  group('moodFor', () {
    test('thresholds 0, 50, 100, 200', () {
      expect(moodFor(0), BrainMood.fresh);
      expect(moodFor(49), BrainMood.fresh);
      expect(moodFor(50), BrainMood.meh);
      expect(moodFor(100), BrainMood.melting);
      expect(moodFor(200), BrainMood.fried);
    });
  });
}
