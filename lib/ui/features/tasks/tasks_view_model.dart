import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories.dart';
import '../../../domain/models.dart';
import '../../app_controller.dart';
import '../../core/widgets/common.dart';

class TasksViewModel extends ChangeNotifier {
  TasksViewModel({required this.app, required this.repo}) {
    app.addListener(_onApp);
    app.signal.addListener(load);
    load();
  }

  factory TasksViewModel.of(BuildContext c) =>
      TasksViewModel(app: c.read<AppController>(), repo: c.read<TasksRepository>());

  final AppController app;
  final TasksRepository repo;

  List<Task> open = const [];
  List<Task> doneToday = const [];
  bool loaded = false;
  String _day = '';
  bool _disposed = false;

  int get starred => open.where((t) => t.isTop3).length;

  void _onApp() {
    if (app.today != _day) load();
  }

  Future<void> load() async {
    _day = app.today;
    await repo.rollover(app.dayStart);
    final r = await repo.list(app.dayStart);
    open = r.open;
    doneToday = r.doneToday;
    loaded = true;
    _notify();
  }

  /// false when a star was asked for but 3 are already starred.
  Future<bool> add(String title, {bool repeat = false, bool top = false}) =>
      repo.add(title, repeatDaily: repeat, top: top);

  Future<void> complete(Task t) async {
    tickHaptic();
    open = open.where((x) => x.id != t.id).toList();
    _notify();
    await repo.setDone(t.id, true);
  }

  Future<void> reopen(Task t) async {
    tickHaptic();
    await repo.setDone(t.id, false);
  }

  Future<void> delete(Task t) async {
    open = open.where((x) => x.id != t.id).toList();
    _notify();
    await repo.delete(t.id);
  }

  Future<void> restore(Task t) => repo.restore(t);

  /// false when 3 are already starred.
  Future<bool> toggleTop(Task t) => repo.setTop(t.id, !t.isTop3);

  Future<void> save(Task t) => repo.update(t);

  /// [newIndex] is already adjusted for the removed item (onReorderItem).
  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = [...open];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    open = list;
    _notify();
    await repo.reorder([for (final t in list) t.id]);
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
