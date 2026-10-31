import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories.dart';
import '../../../data/settings_keys.dart';
import '../../../domain/models.dart';
import '../../../domain/score.dart';
import '../../app_controller.dart';
import '../../core/widgets/common.dart';

class TodayViewModel extends ChangeNotifier {
  TodayViewModel({
    required this.app,
    required this.reels,
    required this.tasks,
    required this.habits,
    required this.usage,
  }) {
    app.addListener(_onApp);
    app.signal.addListener(load);
    load();
  }

  factory TodayViewModel.of(BuildContext c) => TodayViewModel(
        app: c.read<AppController>(),
        reels: c.read<ReelsRepository>(),
        tasks: c.read<TasksRepository>(),
        habits: c.read<HabitsRepository>(),
        usage: c.read<UsageRepository>(),
      );

  final AppController app;
  final ReelsRepository reels;
  final TasksRepository tasks;
  final HabitsRepository habits;
  final UsageRepository usage;

  ReelDay reelDay = const ReelDay.empty('');
  int screenSeconds = 0;
  List<Task> top = const [];
  List<HabitStatus> habitList = const [];
  int topDone = 0;
  int topTotal = 0;
  bool loaded = false;

  String _loadedDay = '';
  DateTime _usageAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;
  int _generation = 0;

  AppSettings get settings => app.settings;
  BrainMood get mood => moodFor(reelDay.total);

  int get score => dailyScore(
        habitsDone: habitList.where((h) => h.doneToday).length,
        habitsTotal: habitList.length,
        topDone: topDone,
        topTotal: topTotal,
        reels: reelDay.total,
        limit: settings.softLimit,
      );

  void _onApp() {
    if (app.today != _loadedDay) {
      load();
    } else {
      _notify(); // settings such as the limit changed colours/labels
    }
  }

  /// Reloads everything. Overlapping loads can finish out of order; only the newest is applied.
  /// Errors (e.g. the database closed for a restore) keep the last good data on screen.
  Future<void> load() async {
    if (!app.database.isOpen) return;
    final gen = ++_generation;
    try {
      await _load(gen);
    } catch (_) {
      // The next signal (restore finished, resume, new data) loads again.
    }
  }

  Future<void> _load(int gen) async {
    final today = app.today;
    await tasks.rollover(app.dayStart);
    final r = await reels.day(today);
    final t = await tasks.list(app.dayStart);
    final h = await habits.statuses(today);
    if (gen != _generation || _disposed) return;

    final starredOpen = t.open.where((x) => x.isTop3).toList();
    final starredDone = t.doneToday.where((x) => x.isTop3).toList();
    if (starredOpen.isNotEmpty || starredDone.isNotEmpty) {
      top = [...starredOpen, ...starredDone].take(3).toList();
      topTotal = starredOpen.length + starredDone.length;
      topDone = starredDone.length;
    } else {
      // Nothing starred: the first open tasks stand in for the top 3.
      // Finished tasks keep their slot so finishing work raises the score.
      final done = t.doneToday.take(3).toList();
      top = [...t.open.take(3 - done.length), ...done];
      topTotal = top.length;
      topDone = done.length;
    }
    reelDay = r;
    habitList = h;
    _loadedDay = today;
    loaded = true;
    _notify();

    // Screen time: ask Android at most once a minute.
    final now = DateTime.now();
    if (now.difference(_usageAt) > const Duration(minutes: 1)) {
      _usageAt = now;
      await usage.refreshDay(today, settings.dayResetHour, until: now);
    }
    final totals = await usage.totals([today]);
    if (gen != _generation || _disposed) return;
    screenSeconds = totals[today] ?? 0;
    _notify();
  }

  Future<void> toggleTask(Task t) async {
    tickHaptic();
    await tasks.setDone(t.id, !t.isDone);
  }

  Future<void> toggleHabit(HabitStatus h) async {
    tickHaptic();
    await habits.setDone(h.habit.id, app.today, !h.doneToday);
  }

  Future<void> setMonitor(bool on) => app.setFlag(SettingsKeys.monitorOn, on);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    app.removeListener(_onApp);
    app.signal.removeListener(load);
    super.dispose();
  }
}
