import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../data/repositories.dart';
import '../../../domain/models.dart';
import '../../app_controller.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';

/// Everything about one day: reels split, screen time, habits ticked, tasks finished, top apps.
Future<void> showDaySheet(BuildContext context, DayRecord record) {
  final history = context.read<HistoryRepository>();
  final usage = context.read<UsageRepository>();
  final app = context.read<AppController>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scroll) => _DayDetail(
        record: record,
        today: app.today,
        load: () async => (
          habits: await history.habitsOn(record.date),
          tasks: await history.tasksOn(record.date, app.settings.dayResetHour),
          apps: await usage.top(record.date, 5),
        ),
        scroll: scroll,
      ),
    ),
  );
}

typedef _DayExtras = ({List<String> habits, List<String> tasks, List<AppUsageEntry> apps});

class _DayDetail extends StatefulWidget {
  const _DayDetail({required this.record, required this.today, required this.load, required this.scroll});

  final DayRecord record;
  final String today;
  final Future<_DayExtras> Function() load;
  final ScrollController scroll;

  @override
  State<_DayDetail> createState() => _DayDetailState();
}

class _DayDetailState extends State<_DayDetail> {
  late final Future<_DayExtras> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final r = widget.record;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Text(formatDayKey(r.date, widget.today), style: context.type.headlineSmall),
        if (formatDayKey(r.date, widget.today) != formatShortDate(r.date, withYear: true))
          Text(formatShortDate(r.date, withYear: true), style: context.type.bodySmall),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${r.reels.total}',
              style: ewText(56, 800, width: 75, height: 0.95, color: c.text, letterSpacing: -1),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('reels', style: context.type.titleMedium),
                  Text(
                    '${r.reels.instagram} Reels · ${r.reels.youtube} Shorts · ${formatDuration(r.reels.seconds)}',
                    style: context.type.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        Container(
          margin: const EdgeInsets.only(top: 18),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: c.surfaceHigh))),
          child: Row(
            children: [
              _Cell(value: formatDuration(r.screenSeconds), label: 'screen time'),
              _Cell(value: '${r.habitsDone}/${r.habitsTotal}', label: 'habits', color: c.good),
              _Cell(value: '${r.tasksDone}', label: 'tasks done', color: c.warn),
            ],
          ),
        ),
        FutureBuilder<_DayExtras>(
          future: _future,
          builder: (context, snap) {
            final d = snap.data;
            if (d == null) {
              return const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            return FadeSlideIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Heading('Habits ticked'),
                  if (d.habits.isEmpty)
                    const _Empty('None that day.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final h in d.habits)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: c.good.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(h, style: context.type.labelLarge),
                          ),
                      ],
                    ),
                  const _Heading('Tasks finished'),
                  if (d.tasks.isEmpty)
                    const _Empty('None that day.')
                  else
                    for (final t in d.tasks)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.check_rounded, size: 18, color: c.good),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(t, style: context.type.bodyLarge)),
                          ],
                        ),
                      ),
                  const _Heading('Most used apps'),
                  if (d.apps.isEmpty)
                    const _Empty('No screen time stored for this day.')
                  else
                    for (final a in d.apps)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(a.label, style: context.type.bodyLarge, overflow: TextOverflow.ellipsis)),
                            Text(formatDuration(a.seconds), style: context.type.labelLarge),
                          ],
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: ewText(20, 760, width: 82, color: color ?? context.ew.text)),
          Text(label, style: context.type.bodySmall),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text, style: context.type.titleMedium),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: context.type.bodyMedium?.copyWith(color: context.ew.muted));
}
