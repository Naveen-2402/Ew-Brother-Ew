import 'dart:convert';

import '../data/settings_keys.dart';

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.isDone,
    required this.isTop3,
    required this.repeatDaily,
    required this.createdAt,
    required this.doneAt,
    required this.position,
    this.remindAt,
  });

  factory Task.fromRow(Map<String, Object?> r) => Task(
        id: r['id'] as int,
        title: r['title'] as String,
        isDone: r['is_done'] == 1,
        isTop3: r['is_top3'] == 1,
        repeatDaily: r['repeat_daily'] == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        doneAt: r['done_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['done_at'] as int),
        position: r['position'] as int,
        remindAt: r['remind_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['remind_at'] as int),
      );

  final int id;
  final String title;
  final bool isDone;
  final bool isTop3;
  final bool repeatDaily;
  final DateTime createdAt;
  final DateTime? doneAt;
  final int position;

  /// Reminder time. Repeat-daily tasks are reminded every day at its time of day.
  final DateTime? remindAt;

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'is_done': isDone ? 1 : 0,
        'is_top3': isTop3 ? 1 : 0,
        'repeat_daily': repeatDaily ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'done_at': doneAt?.millisecondsSinceEpoch,
        'position': position,
        'remind_at': remindAt?.millisecondsSinceEpoch,
      };
}

class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.icon,
    required this.reminderTime,
    required this.isActive,
    required this.position,
    this.target = 1,
    this.remindEvery = 0,
    this.remindUntil,
    this.createdAt,
  });

  factory Habit.fromRow(Map<String, Object?> r) => Habit(
        id: r['id'] as int,
        name: r['name'] as String,
        icon: r['icon'] as String,
        reminderTime: r['reminder_time'] as String?,
        isActive: r['is_active'] == 1,
        position: r['position'] as int,
        target: ((r['target'] as int?) ?? 1).clamp(1, 99),
        remindEvery: (r['remind_every'] as int?) ?? 0,
        remindUntil: r['remind_until'] as String?,
        createdAt: r['created_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      );

  final int id;
  final String name;
  final String icon;

  /// "HH:mm" or null. With [remindEvery] > 0 this is where the reminder range starts.
  final String? reminderTime;
  final bool isActive;
  final int position;

  /// Times per day (1 = a plain yes/no habit, 8 = e.g. 8 glasses of water).
  final int target;

  /// Minutes between reminders, 0 = one reminder at [reminderTime].
  final int remindEvery;

  /// "HH:mm" end of the reminder range when [remindEvery] > 0.
  final String? remindUntil;
  final DateTime? createdAt;

  bool get multi => target > 1;
  bool get interval => reminderTime != null && remindEvery > 0 && remindUntil != null;
}

class HabitStatus {
  const HabitStatus({
    required this.habit,
    required this.doneToday,
    required this.streak,
    required this.last7,
    this.count = 0,
    this.bestStreak = 0,
    this.doneLast30 = 0,
    this.daysLast30 = 1,
    this.totalDone = 0,
    this.doneDays = const {},
  });

  final Habit habit;
  final bool doneToday;
  final int streak;

  /// Oldest first, today last.
  final List<bool> last7;

  /// Times done today (for habits done several times a day).
  final int count;

  /// Longest run of done days (within the last 400 days).
  final int bestStreak;

  /// Done days in the last 30 days, out of [daysLast30] (fewer when the habit is newer).
  final int doneLast30;
  final int daysLast30;

  /// All done days ever.
  final int totalDone;

  /// Day keys done (last 400 days), for the calendar.
  final Set<String> doneDays;

  int get rate30 => daysLast30 <= 0 ? 0 : (doneLast30 * 100 / daysLast30).round();
}

class ReelDay {
  const ReelDay({
    required this.date,
    required this.instagram,
    required this.youtube,
    required this.seconds,
  });

  const ReelDay.empty(this.date)
      : instagram = 0,
        youtube = 0,
        seconds = 0;

  final String date;
  final int instagram;
  final int youtube;
  final int seconds;

  int get total => instagram + youtube;
}

class AppUsageEntry {
  const AppUsageEntry({required this.package, required this.label, required this.seconds});

  final String package;
  final String label;
  final int seconds;
}

enum BubbleSize { small, medium, large }

enum LimitAction { block, pause30 }

/// Immutable snapshot of the settings table.
class AppSettings {
  const AppSettings(this._raw);

  final Map<String, String> _raw;

  /// A copy with [values] applied (used for instant UI updates before the DB write lands).
  AppSettings merge(Map<String, String> values) => AppSettings({..._raw, ...values});

  String _s(String k, String d) => _raw[k] ?? d;
  bool _b(String k, bool d) => _raw.containsKey(k) ? _raw[k] == '1' : d;
  int _i(String k, int d) => int.tryParse(_raw[k] ?? '') ?? d;

  List<String> _list(String k) {
    try {
      final v = jsonDecode(_raw[k] ?? '[]');
      return v is List ? v.whereType<String>().where((s) => s.trim().isNotEmpty).toList() : [];
    } on FormatException {
      return [];
    }
  }

  bool get monitorOn => _b(SettingsKeys.monitorOn, true);
  bool get bubbleOn => _b(SettingsKeys.bubbleOn, true);
  BubbleSize get bubbleSize => switch (_s(SettingsKeys.bubbleSize, 'medium')) {
        'small' => BubbleSize.small,
        'large' => BubbleSize.large,
        _ => BubbleSize.medium,
      };
  int get intervalInstagram => _i(SettingsKeys.intervalInstagram, 10).clamp(1, 100);
  int get intervalYoutube => _i(SettingsKeys.intervalYoutube, 10).clamp(1, 100);
  int get pauseSeconds => _i(SettingsKeys.pauseSeconds, 5).clamp(3, 15);
  bool get limitOn => _b(SettingsKeys.limitOn, true);
  int get limitReels => _i(SettingsKeys.limitReels, 100).clamp(20, 500);
  LimitAction get limitAction =>
      _s(SettingsKeys.limitAction, 'block') == 'pause30' ? LimitAction.pause30 : LimitAction.block;
  int get dayResetHour => _i(SettingsKeys.dayResetHour, 4).clamp(0, 23);

  /// A changed "day starts at" hour waiting for the current day to end, or null.
  int? get pendingResetHour {
    final v = int.tryParse(_raw[SettingsKeys.dayResetNext] ?? '');
    return v?.clamp(0, 23);
  }

  /// The day key that has to end before [pendingResetHour] applies.
  String get pendingResetAfter => _s(SettingsKeys.dayResetNextAfter, '');
  List<String> get messages => _list(SettingsKeys.messages);
  bool get interruptOn => _b(SettingsKeys.interruptOn, false);
  bool get focusOn => _b(SettingsKeys.focusOn, false);
  String get focusStart => _s(SettingsKeys.focusStart, '09:00');
  String get focusEnd => _s(SettingsKeys.focusEnd, '17:00');
  List<String> get focusApps => _list(SettingsKeys.focusApps);
  bool get statusNotifOn => _b(SettingsKeys.statusNotifOn, true);
  bool get morningOn => _b(SettingsKeys.morningOn, true);
  String get morningTime => _s(SettingsKeys.morningTime, '08:00');
  bool get eveningOn => _b(SettingsKeys.eveningOn, true);
  String get eveningTime => _s(SettingsKeys.eveningTime, '21:00');
  bool get weeklyOn => _b(SettingsKeys.weeklyOn, true);
  String get theme => _s(SettingsKeys.theme, 'dark');
  List<String> get extraReelIds => _list(SettingsKeys.extraReelIds);

  /// Limit used for colours and the score even when the hard limit is off.
  int get softLimit => limitOn ? limitReels : 100;
}
