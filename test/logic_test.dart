import 'package:ew_brother_ew/core/format.dart';
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

  group('history dates', () {
    test('day labels', () {
      expect(formatDayKey('2026-11-01', '2026-11-01'), 'Today');
      expect(formatDayKey('2026-10-31', '2026-11-01'), 'Yesterday');
      expect(formatDayKey('2026-10-27', '2026-11-01'), 'Tue 27 Oct');
      expect(formatDayKey('2025-12-30', '2026-01-02'), 'Tue 30 Dec 2025');
    });

    test('previous period sits right before the range', () {
      final range = LogicalDay.lastDays('2026-11-01', 7);
      final prev = LogicalDay.lastDays(LogicalDay.minusDays(range.first, 1), range.length);
      expect(prev.last, '2026-10-25');
      expect(prev.first, '2026-10-19');
      expect(prev.length, 7);
    });

    test('task reminder labels', () {
      final now = DateTime(2026, 11, 1, 10);
      expect(formatReminder(DateTime(2026, 11, 1, 18, 30), daily: false, now: now), 'Today 6:30 PM');
      expect(formatReminder(DateTime(2026, 11, 2, 9, 5), daily: false, now: now), 'Tomorrow 9:05 AM');
      expect(formatReminder(DateTime(2026, 11, 12, 9), daily: false, now: now), '12 Nov, 9:00 AM');
      expect(formatReminder(DateTime(2027, 1, 3, 0, 15), daily: false, now: now), '3 Jan 2027, 12:15 AM');
      expect(formatReminder(DateTime(2026, 10, 1, 7), daily: true, now: now), 'Daily 7:00 AM');
    });
  });
}
