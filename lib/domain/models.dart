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
      );

  final int id;
  final String title;
  final bool isDone;
  final bool isTop3;
  final bool repeatDaily;
  final DateTime createdAt;
  final DateTime? doneAt;
  final int position;

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'is_done': isDone ? 1 : 0,
        'is_top3': isTop3 ? 1 : 0,
        'repeat_daily': repeatDaily ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'done_at': doneAt?.millisecondsSinceEpoch,
        'position': position,
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
  });

  factory Habit.fromRow(Map<String, Object?> r) => Habit(
        id: r['id'] as int,
        name: r['name'] as String,
        icon: r['icon'] as String,
        reminderTime: r['reminder_time'] as String?,
        isActive: r['is_active'] == 1,
        position: r['position'] as int,
      );

  final int id;
  final String name;
  final String icon;

  /// "HH:mm" or null.
  final String? reminderTime;
  final bool isActive;
  final int position;
}

class HabitStatus {
  const HabitStatus({
    required this.habit,
    required this.doneToday,
    required this.streak,
    required this.last7,
  });

  final Habit habit;
  final bool doneToday;
  final int streak;

  /// Oldest first, today last.
  final List<bool> last7;
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
