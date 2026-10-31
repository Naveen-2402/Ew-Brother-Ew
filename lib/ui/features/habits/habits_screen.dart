import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/logical_day.dart';
import '../../../domain/models.dart';
import '../../core/habit_icons.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'habit_editor.dart';
import 'habits_view_model.dart';

/// One tap anywhere on a habit ticks today. Long-press edits.
/// Flat ruled rows instead of cards; the 7-day strip reads like a calendar line.
class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HabitsViewModel>();
    final c = context.ew;
    final week = vm.week;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text('Habits', style: context.type.headlineMedium)),
                TextButton.icon(
                  onPressed: () => showHabitEditor(context),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          if (vm.loaded && vm.habits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _DayTally(done: vm.doneToday, total: vm.habits.length),
            ),
          if (vm.loaded && vm.habits.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text(
                'No habits yet. Start with one small one.',
                style: context.type.bodyLarge?.copyWith(color: c.muted),
              ),
            ),
          for (var i = 0; i < vm.habits.length; i++) ...[
            if (i > 0) Divider(indent: 82, endIndent: 20, color: c.surfaceHigh),
            FadeSlideIn(
              key: ValueKey('habit-${vm.habits[i].habit.id}'),
              index: i,
              child: _HabitRow(status: vm.habits[i], week: week, onTap: () => vm.toggle(vm.habits[i])),
            ),
          ],
          if (vm.loaded && vm.habits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('Tap to tick today. Long-press to edit.', style: context.type.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// "3 of 5 today" with a segmented bar, one segment per habit.
class _DayTally extends StatelessWidget {
  const _DayTally({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Row(
      children: [
        Text.rich(
          TextSpan(
            text: '$done',
            style: ewText(18, 760, width: 82, color: done == total ? c.good : c.text),
            children: [TextSpan(text: ' of $total today', style: context.type.bodySmall)],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < done ? c.good : c.surfaceHigh,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.status, required this.week, required this.onTap});

  final HabitStatus status;
  final List<String> week;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final done = status.doneToday;
    final h = status.habit;

    return InkWell(
      onTap: onTap,
      onLongPress: () => showHabitEditor(context, habit: h),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: done ? c.good : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: done ? c.good : c.surfaceHigh, width: 1.5),
              ),
              child: Icon(
                done ? Icons.check_rounded : habitIcon(h.icon),
                color: done ? c.onAccent : c.text,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.titleMedium?.copyWith(color: done ? c.muted : c.text),
                  ),
                  const SizedBox(height: 8),
                  _WeekStrip(week: week, last7: status.last7),
                  if (h.reminderTime != null) ...[
                    const SizedBox(height: 6),
                    Text('Reminder ${formatClock(h.reminderTime!)}', style: context.type.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Streak(days: status.streak),
          ],
        ),
      ),
    );
  }
}

/// Seven short bars, oldest left, today right. Day letters underneath, today in full ink.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.week, required this.last7});

  final List<String> week;
  final List<bool> last7;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 7,
                decoration: BoxDecoration(
                  color: last7[i] ? c.good : c.surfaceHigh,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                weekdayShort[LogicalDay.parse(week[i]).weekday - 1].substring(0, 1),
                style: ewText(10, i == 6 ? 700 : 500, color: i == 6 ? c.text : c.muted),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Streak as a number with a small caption; turns haldi from 3 days.
class _Streak extends StatelessWidget {
  const _Streak({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final hot = days >= 3;
    return SizedBox(
      width: 44,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('$days', style: ewText(26, 800, width: 78, height: 1, color: hot ? c.warn : c.muted)),
          Text(days == 1 ? 'day' : 'days', style: context.type.labelSmall),
        ],
      ),
    );
  }
}
