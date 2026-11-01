import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/logical_day.dart';
import '../../../domain/models.dart';
import '../../core/habit_icons.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'habit_detail.dart';
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
              child: _HabitRow(
                status: vm.habits[i],
                week: week,
                onTap: () => vm.toggle(vm.habits[i]),
                onMinus: () => vm.decrement(vm.habits[i]),
                onDetail: () => showHabitDetail(context, vm.habits[i], vm.app.today),
              ),
            ),
          ],
          if (vm.loaded && vm.habits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                'Tap to tick today (or add one). Tap the streak for history. Long-press to edit.',
                style: context.type.bodySmall,
              ),
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
  const _HabitRow({
    required this.status,
    required this.week,
    required this.onTap,
    required this.onMinus,
    required this.onDetail,
  });

  final HabitStatus status;
  final List<String> week;
  final VoidCallback onTap;
  final VoidCallback onMinus;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final done = status.doneToday;
    final h = status.habit;

    return InkWell(
      onTap: onTap,
      onLongPress: () => showHabitEditor(context, habit: h),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
        child: Row(
          children: [
            _TickBox(habit: h, done: done, count: status.count),
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
                  if (h.multi) ...[
                    const SizedBox(height: 6),
                    _CountLine(count: status.count, target: h.target, onMinus: onMinus),
                  ],
                  const SizedBox(height: 8),
                  _WeekStrip(week: week, last7: status.last7),
                  if (h.reminderTime != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.notifications_none_rounded, size: 14, color: c.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            habitReminderText(h),
                            style: context.type.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            _Streak(days: status.streak, best: status.bestStreak, onTap: onDetail),
          ],
        ),
      ),
    );
  }
}

/// Plain habit: icon, then a filled check. Several a day: the count, filling up from the bottom.
class _TickBox extends StatelessWidget {
  const _TickBox({required this.habit, required this.done, required this.count});

  final Habit habit;
  final bool done;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final fill = habit.multi ? (count / habit.target).clamp(0.0, 1.0) : (done ? 1.0 : 0.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: done ? c.good : c.surfaceHigh, width: 1.5),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: fill),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => FractionallySizedBox(
                  heightFactor: v,
                  widthFactor: 1,
                  child: ColoredBox(color: done ? c.good : c.good.withValues(alpha: 0.28)),
                ),
              ),
            ),
            Center(
              child: done
                  ? Icon(Icons.check_rounded, color: c.onAccent, size: 22)
                  : habit.multi
                      ? Text('$count', style: ewText(18, 780, width: 80, color: c.text))
                      : Icon(habitIcon(habit.icon), color: c.text, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

/// "3 of 8 today" with a − to undo a stray tap.
class _CountLine extends StatelessWidget {
  const _CountLine({required this.count, required this.target, required this.onMinus});

  final int count;
  final int target;
  final VoidCallback onMinus;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Row(
      children: [
        Text.rich(
          TextSpan(
            text: '$count',
            style: ewText(14, 740, color: count >= target ? c.good : c.text),
            children: [TextSpan(text: ' of $target today', style: context.type.bodySmall)],
          ),
        ),
        const SizedBox(width: 6),
        if (count > 0)
          SizedBox(
            width: 32,
            height: 28,
            child: IconButton(
              tooltip: 'One less',
              padding: EdgeInsets.zero,
              iconSize: 18,
              onPressed: onMinus,
              icon: Icon(Icons.remove_circle_outline_rounded, color: c.muted),
            ),
          ),
      ],
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

/// Streak with a flame (haldi from 3 days) and the best streak under it. Tap for history.
class _Streak extends StatelessWidget {
  const _Streak({required this.days, required this.best, required this.onTap});

  final int days;
  final int best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final hot = days >= 3;
    return Semantics(
      button: true,
      label: '$days day streak, best $best. Show history.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 16,
                      color: days > 0 ? (hot ? c.warn : c.muted) : c.surfaceHigh,
                    ),
                    const SizedBox(width: 2),
                    Text('$days', style: ewText(24, 800, width: 78, height: 1, color: hot ? c.warn : c.text)),
                  ],
                ),
                const SizedBox(height: 2),
                Text('best $best', style: context.type.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
