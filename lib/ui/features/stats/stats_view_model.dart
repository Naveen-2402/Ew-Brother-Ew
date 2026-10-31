import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/logical_day.dart';
import '../../../data/repositories.dart';
import '../../../domain/models.dart';
import '../../app_controller.dart';

class StatsViewModel extends ChangeNotifier {
  StatsViewModel({required this.app, required this.reels, required this.usage}) {
    app.signal.addListener(load);
    load();
  }

  factory StatsViewModel.of(BuildContext c) => StatsViewModel(
        app: c.read<AppController>(),
        reels: c.read<ReelsRepository>(),
        usage: c.read<UsageRepository>(),
      );

  final AppController app;
  final ReelsRepository reels;
  final UsageRepository usage;

  /// Oldest first, today last.
  List<ReelDay> week = const [];
  List<AppUsageEntry> topApps = const [];

  /// Screen time per day, same order as [week].
  List<int> screenWeek = const [];
  bool loaded = false;
  bool _backfilled = false;
  bool _disposed = false;

  int get weekTotal => week.fold(0, (s, d) => s + d.total);
  int get weekAverage => week.isEmpty ? 0 : (weekTotal / week.length).round();

  Future<void> load() async {
    final today = app.today;
    final days = LogicalDay.lastDays(today, 7);
    final r = await reels.days(days);
    week = [for (final d in days) r[d]!];

    if (!_backfilled) {
      _backfilled = true;
      await usage.backfill(days.sublist(0, 6), app.settings.dayResetHour);
    }
    final totals = await usage.totals(days);
    screenWeek = [for (final d in days) totals[d] ?? 0];
    topApps = await usage.top(today, 5);
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    app.signal.removeListener(load);
    super.dispose();
  }
}
