import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/logical_day.dart';
import '../../../data/repositories.dart';
import '../../../domain/models.dart';
import '../../app_controller.dart';
import '../../core/widgets/common.dart';

class HabitsViewModel extends ChangeNotifier {
  HabitsViewModel({required this.app, required this.repo}) {
    app.addListener(_onApp);
    app.signal.addListener(load);
    load();
  }

  factory HabitsViewModel.of(BuildContext c) =>
      HabitsViewModel(app: c.read<AppController>(), repo: c.read<HabitsRepository>());

  final AppController app;
  final HabitsRepository repo;

  List<HabitStatus> habits = const [];
  bool loaded = false;
  String _day = '';
  bool _disposed = false;
  int _generation = 0;

  int get doneToday => habits.where((h) => h.doneToday).length;

  /// Day keys for the 7-dot row, oldest first.
  List<String> get week => LogicalDay.lastDays(app.today, 7);

  void _onApp() {
    if (app.today != _day) load();
  }

  Future<void> load() async {
    if (!app.database.isOpen) return;
    final gen = ++_generation;
    _day = app.today;
    final List<HabitStatus> next;
    try {
      next = await repo.statuses(app.today);
    } catch (_) {
      return;
    }
    if (gen != _generation || _disposed) return;
    habits = next;
    loaded = true;
    _notify();
  }

  /// Plain habit: tick / untick. Several-times-a-day habit: one more.
  Future<void> toggle(HabitStatus h) async {
    tickHaptic();
    if (h.habit.multi) {
      await repo.addCount(h.habit.id, app.today, 1);
    } else {
      await repo.setDone(h.habit.id, app.today, !h.doneToday);
    }
  }

  /// One less (undo a stray tap on a several-times-a-day habit).
  Future<void> decrement(HabitStatus h) async {
    if (h.count <= 0) return;
    tickHaptic();
    await repo.addCount(h.habit.id, app.today, -1);
  }

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
