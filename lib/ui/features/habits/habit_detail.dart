import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/logical_day.dart';
import '../../../domain/models.dart';
import '../../core/habit_icons.dart';
import '../../core/theme.dart';
import 'habit_editor.dart';

/// Streaks and history for one habit: current and best streak, last 30 days, total,
/// a five-week calendar and the reminder setup.
Future<void> showHabitDetail(BuildContext context, HabitStatus status, String today) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HabitDetail(status: status, today: today, outer: context),
  );
}

String habitReminderText(Habit h) {
  if (h.reminderTime == null) return 'No reminder';
  if (h.interval) {
    final m = h.remindEvery;
    final every = m < 60 ? '$m min' : (m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min');
    return 'Every $every, ${formatClock(h.reminderTime!)} to ${formatClock(h.remindUntil!)}';
  }
  return 'Reminder ${formatClock(h.reminderTime!)}';
}

class _HabitDetail extends StatelessWidget {
  const _HabitDetail({required this.status, required this.today, required this.outer});

  final HabitStatus status;
  final String today;
  final BuildContext outer;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final h = status.habit;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(14)),
                  child: Icon(habitIcon(h.icon), color: c.text, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.name, style: context.type.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(
                        h.multi ? '${h.target} times a day · ${habitReminderText(h)}' : habitReminderText(h),
                        style: context.type.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Big streak figure, with best streak beside it.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 34,
                  color: status.streak > 0 ? c.warn : c.surfaceHigh,
                ),
                const SizedBox(width: 6),
                Text(
                  '${status.streak}',
                  style: ewText(56, 800, width: 78, height: 0.95, color: status.streak > 0 ? c.text : c.muted),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('day streak', style: context.type.titleSmall),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${status.bestStreak}', style: ewText(22, 760, width: 82, color: c.text)),
                      Text('best', style: context.type.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
            if (!status.doneToday && status.streak > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  h.multi
                      ? '${status.count} of ${h.target} today. Finish today to keep the streak.'
                      : 'Tick it today to keep the streak.',
                  style: context.type.bodySmall?.copyWith(color: c.warn),
                ),
              ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: c.surfaceHigh))),
              child: Row(
                children: [
                  Expanded(child: _Fig(value: '${status.rate30}%', label: 'last 30 days')),
                  Container(width: 1, height: 34, color: c.surfaceHigh),
                  Expanded(child: _Fig(value: '${status.doneLast30}/${status.daysLast30}', label: 'days done', pad: true)),
                  Container(width: 1, height: 34, color: c.surfaceHigh),
                  Expanded(child: _Fig(value: '${status.totalDone}', label: 'all time', pad: true)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text('Last 5 weeks', style: context.type.titleSmall),
            const SizedBox(height: 10),
            _Calendar(done: status.doneDays, today: today),
            const SizedBox(height: 20),
            Row(
              children: [
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (outer.mounted) showHabitEditor(outer, habit: h);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit habit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Fig extends StatelessWidget {
  const _Fig({required this.value, required this.label, this.pad = false});

  final String value;
  final String label;
  final bool pad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: pad ? 14 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: ewText(22, 760, width: 82, color: context.ew.text)),
          Text(label, style: context.type.bodySmall),
        ],
      ),
    );
  }
}

/// Five weeks, Monday first, ending with the current week. Done days filled, today outlined.
class _Calendar extends StatelessWidget {
  const _Calendar({required this.done, required this.today});

  final Set<String> done;
  final String today;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final t = LogicalDay.parse(today);
    // Sunday of this week is the last cell; 35 cells back from there.
    final lastCell = LogicalDay.minusDays(today, -(7 - t.weekday));
    final cells = LogicalDay.lastDays(lastCell, 35);
    return Column(
      children: [
        Row(
          children: [
            for (final d in weekdayShort)
              Expanded(
                child: Center(child: Text(d.substring(0, 1), style: context.type.labelSmall)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var w = 0; w < 5; w++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: () {
                      final key = cells[w * 7 + i];
                      final future = key.compareTo(today) > 0;
                      final isDone = done.contains(key);
                      final isToday = key == today;
                      return Center(
                        child: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isDone ? c.good : (future ? Colors.transparent : c.surfaceHigh.withValues(alpha: 0.6)),
                            borderRadius: BorderRadius.circular(10),
                            border: isToday ? Border.all(color: c.text, width: 1.5) : null,
                          ),
                          child: Text(
                            '${LogicalDay.parse(key).day}',
                            style: ewText(
                              12,
                              isToday ? 700 : 520,
                              color: isDone ? c.onAccent : (future ? c.surfaceHigh : c.muted),
                            ),
                          ),
                        ),
                      );
                    }(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
