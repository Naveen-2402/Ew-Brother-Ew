import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/logical_day.dart';
import '../core/native_bridge.dart';
import '../domain/models.dart';
import 'app_database.dart';

/// Bumped after any data write so every view model can reload.
class DataSignal extends ChangeNotifier {
  void bump() => notifyListeners();
}

// ============================================================================ settings

class SettingsRepository {
  SettingsRepository(this._db, this._bridge);

  final AppDatabase _db;
  final NativeBridge _bridge;

  Future<AppSettings> load() async {
    final rows = await _db.db.query('settings');
    return AppSettings({for (final r in rows) r['key'] as String: r['value'] as String});
  }

  Future<void> set(Map<String, String> values) async {
    final batch = _db.db.batch();
    values.forEach((k, v) {
      batch.insert('settings', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
    await _bridge.settingsChanged();
  }

  static String encodeList(List<String> list) => jsonEncode(list);
}

// ============================================================================ reels

class ReelsRepository {
  ReelsRepository(this._db);

  final AppDatabase _db;

  Future<Map<String, ReelDay>> days(List<String> keys) async {
    if (keys.isEmpty) return {};
    final rows = await _db.db.query(
      'daily_stats',
      where: 'date >= ? AND date <= ?',
      whereArgs: [keys.first, keys.last],
    );
    final out = {for (final k in keys) k: ReelDay.empty(k)};
    for (final r in rows) {
      final date = r['date'] as String;
      final cur = out[date];
      if (cur == null) continue;
      final count = r['reel_count'] as int;
      final secs = r['reel_seconds'] as int;
      out[date] = ReelDay(
        date: date,
        instagram: cur.instagram + (r['app'] == 'instagram' ? count : 0),
        youtube: cur.youtube + (r['app'] == 'youtube' ? count : 0),
        seconds: cur.seconds + secs,
      );
    }
    return out;
  }

  Future<ReelDay> day(String key) async => (await days([key]))[key]!;
}

// ============================================================================ tasks

class TasksRepository {
  TasksRepository(this._db, this._bridge, this._signal, this._dayStart);

  final AppDatabase _db;
  final NativeBridge _bridge;
  final DataSignal _signal;

  /// Start of the current logical day (from AppController).
  final DateTime Function() _dayStart;

  static const maxTop = 3;

  Future<void> _changed() async {
    _signal.bump();
    await _bridge.dataChanged();
  }

  /// Repeat-daily tasks done before today become open again.
  Future<void> rollover(DateTime dayStart) => _db.db.rawUpdate(
        'UPDATE tasks SET is_done = 0, done_at = NULL '
        'WHERE repeat_daily = 1 AND is_done = 1 AND done_at < ?',
        [dayStart.millisecondsSinceEpoch],
      );

  /// Open tasks in list order, plus tasks finished since [dayStart].
  Future<({List<Task> open, List<Task> doneToday})> list(DateTime dayStart) async {
    final open = await _db.db.query('tasks', where: 'is_done = 0', orderBy: 'position ASC, id ASC');
    final done = await _db.db.query(
      'tasks',
      where: 'is_done = 1 AND done_at >= ?',
      whereArgs: [dayStart.millisecondsSinceEpoch],
      orderBy: 'done_at DESC',
    );
    return (open: open.map(Task.fromRow).toList(), doneToday: done.map(Task.fromRow).toList());
  }

  /// Returns false if a star was requested but 3 tasks are already starred
  /// (the task is still added, unstarred).
  Future<bool> add(String title, {bool repeatDaily = false, bool top = false}) async {
    final t = title.trim();
    if (t.isEmpty) return true;
    final r = await _db.db.rawQuery('SELECT COALESCE(MAX(position), 0) + 1 AS p FROM tasks');
    var makeTop = top;
    if (makeTop) {
      makeTop = await _topCount() < maxTop;
    }
    await _db.db.insert('tasks', {
      'title': t,
      'is_done': 0,
      'is_top3': makeTop ? 1 : 0,
      'repeat_daily': repeatDaily ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'position': r.first['p'] as int,
    });
    await _changed();
    return makeTop == top;
  }

  /// Starred tasks for today: open ones plus ones finished today, so the cap is 3 per day.
  Future<int> _topCount() async {
    final r = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM tasks WHERE is_top3 = 1 AND (is_done = 0 OR done_at >= ?)',
      [_dayStart().millisecondsSinceEpoch],
    );
    return r.first['c'] as int;
  }

  Future<void> setDone(int id, bool done) async {
    if (!done) {
      // Un-ticking: forget this completion in history (the trigger logged it on tick).
      await _db.db.rawDelete(
        'DELETE FROM task_log WHERE task_id = ? AND done_at = (SELECT done_at FROM tasks WHERE id = ?)',
        [id, id],
      );
    }
    await _db.db.update(
      'tasks',
      {'is_done': done ? 1 : 0, 'done_at': done ? DateTime.now().millisecondsSinceEpoch : null},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _changed();
  }

  /// Returns false when 3 tasks are already starred.
  Future<bool> setTop(int id, bool top) async {
    if (top && await _topCount() >= maxTop) return false;
    await _db.db.update('tasks', {'is_top3': top ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    await _changed();
    return true;
  }

  Future<void> update(Task t) async {
    await _db.db.update('tasks', t.toRow(), where: 'id = ?', whereArgs: [t.id]);
    await _changed();
  }

  /// Edit sheet: only the fields the sheet shows. Done state, order and star are left alone,
  /// so a tick made meanwhile (e.g. from a notification) is never undone by saving.
  Future<void> edit(int id, {required String title, required bool repeatDaily}) async {
    final t = title.trim();
    if (t.isEmpty) return;
    await _db.db.update(
      'tasks',
      {'title': t, 'repeat_daily': repeatDaily ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _changed();
  }

  Future<void> delete(int id) async {
    await _db.db.delete('tasks', where: 'id = ?', whereArgs: [id]);
    await _changed();
  }

  /// Undo for delete: puts the exact row back.
  Future<void> restore(Task t) async {
    await _db.db.insert('tasks', t.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
    await _changed();
  }

  Future<void> reorder(List<int> idsInOrder) async {
    final batch = _db.db.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update('tasks', {'position': i}, where: 'id = ?', whereArgs: [idsInOrder[i]]);
    }
    await batch.commit(noResult: true);
    await _changed();
  }
}

// ============================================================================ habits

class HabitsRepository {
  HabitsRepository(this._db, this._bridge, this._signal);

  final AppDatabase _db;
  final NativeBridge _bridge;
  final DataSignal _signal;

  Future<void> _changed() async {
    _signal.bump();
    await _bridge.dataChanged();
  }

  Future<List<HabitStatus>> statuses(String today) async {
    final habits = (await _db.db.query('habits', where: 'is_active = 1', orderBy: 'position ASC, id ASC'))
        .map(Habit.fromRow)
        .toList();
    if (habits.isEmpty) return [];
    // 400 days is plenty for streaks and keeps the query small.
    final since = LogicalDay.minusDays(today, 400);
    final logs = await _db.db.query(
      'habit_logs',
      columns: ['habit_id', 'date'],
      where: 'done = 1 AND date >= ?',
      whereArgs: [since],
    );
    final doneDays = <int, Set<String>>{};
    for (final l in logs) {
      doneDays.putIfAbsent(l['habit_id'] as int, () => <String>{}).add(l['date'] as String);
    }
    final week = LogicalDay.lastDays(today, 7);
    return [
      for (final h in habits)
        HabitStatus(
          habit: h,
          doneToday: doneDays[h.id]?.contains(today) ?? false,
          streak: _streak(doneDays[h.id] ?? const <String>{}, today),
          last7: [for (final d in week) doneDays[h.id]?.contains(d) ?? false],
        ),
    ];
  }

  /// Consecutive days ending today; if today isn't ticked yet, ending yesterday.
  static int _streak(Set<String> days, String today) {
    var day = days.contains(today) ? today : LogicalDay.minusDays(today, 1);
    var n = 0;
    while (days.contains(day)) {
      n++;
      day = LogicalDay.minusDays(day, 1);
    }
    return n;
  }

  Future<void> setDone(int habitId, String day, bool done) async {
    await _db.db.insert(
      'habit_logs',
      {'habit_id': habitId, 'date': day, 'done': done ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _changed();
  }

  Future<void> add(String name, String icon, String? reminder) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final r = await _db.db.rawQuery('SELECT COALESCE(MAX(position), 0) + 1 AS p FROM habits');
    await _db.db.insert('habits', {
      'name': n,
      'icon': icon,
      'reminder_time': reminder,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'position': r.first['p'] as int,
    });
    await _changed();
  }

  Future<void> update(int id, String name, String icon, String? reminder) async {
    await _db.db.update(
      'habits',
      {'name': name.trim(), 'icon': icon, 'reminder_time': reminder},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _changed();
  }

  Future<void> delete(int id) async {
    await _db.db.transaction((txn) async {
      await txn.delete('habit_logs', where: 'habit_id = ?', whereArgs: [id]);
      await txn.delete('habits', where: 'id = ?', whereArgs: [id]);
    });
    await _changed();
  }

  /// Done ticks per day for [days] (all habits).
  Future<Map<String, int>> doneCounts(List<String> days) async {
    if (days.isEmpty) return {};
    final rows = await _db.db.rawQuery(
      'SELECT date, COUNT(*) AS c FROM habit_logs WHERE done = 1 AND date >= ? AND date <= ? GROUP BY date',
      [days.first, days.last],
    );
    return {for (final r in rows) r['date'] as String: r['c'] as int};
  }
}

// ============================================================================ usage

class UsageRepository {
  UsageRepository(this._db, this._bridge);

  final AppDatabase _db;
  final NativeBridge _bridge;

  static const _reelPackages = {
    'com.instagram.android': 'instagram',
    'com.google.android.youtube': 'youtube',
  };

  /// Reads screen time for one logical day from Android and stores it.
  Future<void> refreshDay(String day, int resetHour, {DateTime? until}) async {
    final start = LogicalDay.startOf(day, resetHour);
    final end = until ?? start.add(const Duration(days: 1));
    final list = await _bridge.usage(start, end);
    if (list.isEmpty) return; // no usage access, or nothing recorded: keep what we have
    await _db.db.transaction((txn) async {
      await txn.delete('app_usage', where: 'date = ?', whereArgs: [day]);
      for (final e in list) {
        await txn.insert('app_usage', {
          'date': day,
          'package_name': e.package,
          'app_label': e.label,
          'seconds': e.seconds,
        });
        final app = _reelPackages[e.package];
        if (app != null) {
          await txn.rawInsert('INSERT OR IGNORE INTO daily_stats(date, app) VALUES (?, ?)', [day, app]);
          await txn.rawUpdate(
            'UPDATE daily_stats SET screen_seconds = ? WHERE date = ? AND app = ?',
            [e.seconds, day, app],
          );
        }
      }
    });
  }

  /// Fills past days that have no stored usage yet (Android keeps a few days of events).
  Future<void> backfill(List<String> pastDays, int resetHour) async {
    if (pastDays.isEmpty) return;
    final rows = await _db.db.rawQuery(
      'SELECT DISTINCT date FROM app_usage WHERE date >= ? AND date <= ?',
      [pastDays.first, pastDays.last],
    );
    final have = {for (final r in rows) r['date'] as String};
    for (final d in pastDays) {
      if (!have.contains(d)) await refreshDay(d, resetHour);
    }
  }

  Future<List<AppUsageEntry>> top(String day, int limit) async {
    final rows = await _db.db.query(
      'app_usage',
      where: 'date = ?',
      whereArgs: [day],
      orderBy: 'seconds DESC',
      limit: limit,
    );
    return [
      for (final r in rows)
        AppUsageEntry(
          package: r['package_name'] as String,
          label: r['app_label'] as String,
          seconds: r['seconds'] as int,
        ),
    ];
  }

  Future<Map<String, int>> totals(List<String> days) async {
    if (days.isEmpty) return {};
    final rows = await _db.db.rawQuery(
      'SELECT date, SUM(seconds) AS s FROM app_usage WHERE date >= ? AND date <= ? GROUP BY date',
      [days.first, days.last],
    );
    return {for (final r in rows) r['date'] as String: (r['s'] as num).toInt()};
  }
}

// ============================================================================ history

/// Everything known about one past day.
class DayRecord {
  const DayRecord({
    required this.date,
    required this.reels,
    required this.screenSeconds,
    required this.habitsDone,
    required this.habitsTotal,
    required this.tasksDone,
  });

  final String date;
  final ReelDay reels;
  final int screenSeconds;
  final int habitsDone;

  /// Habits that existed on that day (still active ones only; deleted habits are gone).
  final int habitsTotal;
  final int tasksDone;
}

/// Read-only queries over any date range for the Stats/history screen.
class HistoryRepository {
  HistoryRepository(this._db, this._reels, this._usage, this._habits);

  final AppDatabase _db;
  final ReelsRepository _reels;
  final UsageRepository _usage;
  final HabitsRepository _habits;

  /// [days] oldest first, consecutive.
  Future<List<DayRecord>> range(List<String> days, int resetHour) async {
    if (days.isEmpty) return const [];
    final reels = await _reels.days(days);
    final screen = await _usage.totals(days);
    final habitsDone = await _habits.doneCounts(days);
    final tasks = await _tasksDone(days, resetHour);
    final created = (await _db.db.query('habits', columns: ['created_at'], where: 'is_active = 1'))
        .map((r) => r['created_at'] as int)
        .toList();
    return [
      for (final d in days)
        DayRecord(
          date: d,
          reels: reels[d]!,
          screenSeconds: screen[d] ?? 0,
          habitsDone: habitsDone[d] ?? 0,
          habitsTotal: () {
            final end = LogicalDay.startOf(d, resetHour).add(const Duration(days: 1)).millisecondsSinceEpoch;
            return created.where((c) => c < end).length;
          }(),
          tasksDone: tasks[d] ?? 0,
        ),
    ];
  }

  Future<Map<String, int>> _tasksDone(List<String> days, int resetHour) async {
    final start = LogicalDay.startOf(days.first, resetHour).millisecondsSinceEpoch;
    final end = LogicalDay.startOf(days.last, resetHour).add(const Duration(days: 1)).millisecondsSinceEpoch;
    final rows = await _db.db.query(
      'task_log',
      columns: ['done_at'],
      where: 'done_at >= ? AND done_at < ?',
      whereArgs: [start, end],
    );
    final out = <String, int>{};
    for (final r in rows) {
      final key = LogicalDay.keyFor(DateTime.fromMillisecondsSinceEpoch(r['done_at'] as int), resetHour);
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  /// Most used apps summed over the range.
  Future<List<AppUsageEntry>> topApps(List<String> days, int limit) async {
    if (days.isEmpty) return const [];
    final rows = await _db.db.rawQuery(
      'SELECT package_name, MAX(app_label) AS label, SUM(seconds) AS s FROM app_usage '
      'WHERE date >= ? AND date <= ? GROUP BY package_name ORDER BY s DESC LIMIT ?',
      [days.first, days.last, limit],
    );
    return [
      for (final r in rows)
        AppUsageEntry(
          package: r['package_name'] as String,
          label: r['label'] as String,
          seconds: (r['s'] as num).toInt(),
        ),
    ];
  }

  /// Names of habits ticked on [day].
  Future<List<String>> habitsOn(String day) async {
    final rows = await _db.db.rawQuery(
      'SELECT h.name FROM habit_logs l JOIN habits h ON h.id = l.habit_id '
      'WHERE l.date = ? AND l.done = 1 ORDER BY h.position, h.id',
      [day],
    );
    return [for (final r in rows) r['name'] as String];
  }

  /// Titles of tasks finished on [day].
  Future<List<String>> tasksOn(String day, int resetHour) async {
    final start = LogicalDay.startOf(day, resetHour);
    final rows = await _db.db.query(
      'task_log',
      columns: ['title'],
      where: 'done_at >= ? AND done_at < ?',
      whereArgs: [start.millisecondsSinceEpoch, start.add(const Duration(days: 1)).millisecondsSinceEpoch],
      orderBy: 'done_at ASC',
    );
    return [for (final r in rows) r['title'] as String];
  }

  /// First day the app actually tracked something (a reel, a habit tick or a finished task).
  /// Screen-time backfill rows from before install don't count, so averages aren't diluted.
  Future<String?> firstDay(int resetHour) async {
    final r = await _db.db.rawQuery(
      'SELECT MIN(d) AS d FROM ('
      'SELECT MIN(date) AS d FROM daily_stats WHERE reel_count > 0 '
      'UNION ALL SELECT MIN(date) FROM reel_events '
      'UNION ALL SELECT MIN(date) FROM habit_logs WHERE done = 1)',
    );
    var first = r.first['d'] as String?;
    final t = await _db.db.rawQuery('SELECT MIN(done_at) AS t FROM task_log');
    final ms = t.first['t'] as int?;
    if (ms != null) {
      final k = LogicalDay.keyFor(DateTime.fromMillisecondsSinceEpoch(ms), resetHour);
      if (first == null || k.compareTo(first) < 0) first = k;
    }
    return first;
  }

  /// First day with stored screen time (Android keeps about a week from before install).
  Future<String?> firstUsageDay() async {
    final r = await _db.db.rawQuery('SELECT MIN(date) AS d FROM app_usage');
    return r.first['d'] as String?;
  }
}
