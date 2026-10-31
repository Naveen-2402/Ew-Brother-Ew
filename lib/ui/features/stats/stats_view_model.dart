import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/logical_day.dart';
import '../../../data/repositories.dart';
import '../../../domain/models.dart';
import '../../app_controller.dart';

enum RangePreset {
  week(7, '7 days'),
  month(30, '30 days'),
  quarter(90, '90 days'),
  year(365, '1 year'),
  custom(0, 'Custom');

  const RangePreset(this.days, this.label);
  final int days;
  final String label;
}

enum Metric {
  reels('Reels'),
  screen('Screen time'),
  habits('Habits'),
  tasks('Tasks');

  const Metric(this.label);
  final String label;

  /// For reels and screen time, less is better.
  bool get lowerIsBetter => this == Metric.reels || this == Metric.screen;
}

enum AppFilter {
  all('Both'),
  instagram('Instagram'),
  youtube('YouTube');

  const AppFilter(this.label);
  final String label;
}

/// History over any range: presets or a custom range, one metric at a time,
/// compared with the period of the same length just before it.
class StatsViewModel extends ChangeNotifier {
  StatsViewModel({required this.app, required this.history, required this.usage}) {
    app.signal.addListener(load);
    load();
  }

  factory StatsViewModel.of(BuildContext c) => StatsViewModel(
        app: c.read<AppController>(),
        history: c.read<HistoryRepository>(),
        usage: c.read<UsageRepository>(),
      );

  /// Longest custom range we load at once.
  static const maxDays = 366;

  final AppController app;
  final HistoryRepository history;
  final UsageRepository usage;

  RangePreset preset = RangePreset.week;
  Metric metric = Metric.reels;
  AppFilter appFilter = AppFilter.all;

  /// Inclusive logical-day keys for [RangePreset.custom].
  String? customFrom;
  String? customTo;

  /// Oldest first.
  List<DayRecord> records = const [];
  List<DayRecord> previous = const [];
  List<AppUsageEntry> topApps = const [];

  /// First day the app tracked anything; earlier days are not averaged.
  String? firstDay;

  /// First day with stored screen time (can be before install: Android keeps about a week).
  String? firstUsageDay;
  bool loaded = false;
  bool busy = false;

  bool _backfilled = false;
  bool _disposed = false;
  int _generation = 0;

  String get today => app.today;
  String get from => records.isEmpty ? today : records.first.date;
  String get to => records.isEmpty ? today : records.last.date;

  List<String> _days() {
    if (preset == RangePreset.custom && customFrom != null && customTo != null) {
      final out = <String>[];
      var d = customFrom!;
      while (d.compareTo(customTo!) <= 0 && out.length < maxDays) {
        out.add(d);
        d = LogicalDay.minusDays(d, -1);
      }
      return out;
    }
    final n = preset == RangePreset.custom ? 7 : preset.days;
    return LogicalDay.lastDays(today, n);
  }

  Future<void> load() async {
    if (!app.database.isOpen) return;
    final gen = ++_generation;
    busy = true;
    _notify();
    try {
      await _load(gen);
    } catch (_) {
      // Database closed mid-load (restore) or a query failed: keep the last data, stop the spinner.
    } finally {
      if (gen == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> _load(int gen) async {
    final reset = app.settings.dayResetHour;
    if (!_backfilled) {
      _backfilled = true;
      // Android keeps roughly a week of usage events; store them before they expire.
      await usage.backfill(LogicalDay.lastDays(today, 8).sublist(0, 7), reset);
    }
    final days = _days();
    final prevDays = LogicalDay.lastDays(LogicalDay.minusDays(days.first, 1), days.length);
    final recs = await history.range(days, reset);
    final prev = await history.range(prevDays, reset);
    final apps = await history.topApps(days, 6);
    final first = await history.firstDay(reset);
    final firstUsage = await history.firstUsageDay();
    if (gen != _generation || _disposed) return; // a newer load started

    records = recs;
    previous = prev;
    topApps = apps;
    // Nothing tracked yet: today is the first day.
    firstDay = first ?? today;
    firstUsageDay = firstUsage ?? today;
    loaded = true;
  }

  void setPreset(RangePreset p) {
    if (p == preset && p != RangePreset.custom) return;
    preset = p;
    load();
  }

  void setCustom(DateTime start, DateTime end) {
    customFrom = LogicalDay.format(start);
    customTo = LogicalDay.format(end);
    preset = RangePreset.custom;
    load();
  }

  void setMetric(Metric m) {
    if (m == metric) return;
    metric = m;
    _notify();
  }

  void setAppFilter(AppFilter f) {
    if (f == appFilter) return;
    appFilter = f;
    _notify();
  }

  // ---------------------------------------------------------------- derived numbers

  /// Value of the current metric for one day. Screen time in seconds.
  int value(DayRecord r) => switch (metric) {
        Metric.reels => switch (appFilter) {
            AppFilter.all => r.reels.total,
            AppFilter.instagram => r.reels.instagram,
            AppFilter.youtube => r.reels.youtube,
          },
        Metric.screen => r.screenSeconds,
        Metric.habits => r.habitsDone,
        Metric.tasks => r.tasksDone,
      };

  /// The first day that counts for the current metric.
  String? get startDay => metric == Metric.screen ? firstUsageDay : firstDay;

  /// Days that count for averages: on or after the first tracked day, never after today.
  List<DayRecord> _tracked(List<DayRecord> list) {
    final start = startDay;
    return [
      for (final r in list)
        if ((start == null || r.date.compareTo(start) >= 0) && r.date.compareTo(today) <= 0) r,
    ];
  }

  bool isTracked(DayRecord r) {
    final start = startDay;
    return start == null || r.date.compareTo(start) >= 0;
  }

  int get total => records.fold(0, (s, r) => s + value(r));
  int get previousTotal => previous.fold(0, (s, r) => s + value(r));

  int get average {
    final t = _tracked(records);
    if (t.isEmpty) return 0;
    return (t.fold<int>(0, (s, r) => s + value(r)) / t.length).round();
  }

  /// Daily average now vs the previous period, in percent. Null when the previous period
  /// wasn't mostly tracked (e.g. your first weeks), so it never shows a misleading +400%.
  int? get changePercent {
    // Today is still running; leave it out so a half day doesn't look like an improvement.
    final cur = _tracked(records).where((r) => r.date != today || records.length == 1).toList();
    final prev = _tracked(previous);
    if (cur.isEmpty || prev.length * 2 < previous.length) return null;
    final curAvg = cur.fold<int>(0, (s, r) => s + value(r)) / cur.length;
    final prevAvg = prev.fold<int>(0, (s, r) => s + value(r)) / prev.length;
    if (prevAvg == 0) return null;
    return ((curAvg - prevAvg) * 100 / prevAvg).round();
  }

  /// Best and worst tracked day (excluding today, which is still running).
  ({DayRecord? best, DayRecord? worst}) get extremes {
    final t = _tracked(records).where((r) => r.date != today).toList();
    if (t.length < 2) return (best: null, worst: null);
    t.sort((a, b) => value(a).compareTo(value(b)));
    return metric.lowerIsBetter ? (best: t.first, worst: t.last) : (best: t.last, worst: t.first);
  }

  /// Habits completion over tracked days, 0..100.
  int get habitRate {
    final t = _tracked(records);
    final possible = t.fold<int>(0, (s, r) => s + r.habitsTotal);
    if (possible == 0) return 0;
    return (t.fold<int>(0, (s, r) => s + r.habitsDone) * 100 / possible).round().clamp(0, 100);
  }

  int get instagramTotal => records.fold(0, (s, r) => s + r.reels.instagram);
  int get youtubeTotal => records.fold(0, (s, r) => s + r.reels.youtube);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    app.signal.removeListener(load);
    super.dispose();
  }
}
