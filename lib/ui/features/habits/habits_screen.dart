import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/logical_day.dart';
import '../../../domain/models.dart';
import '../../core/habit_icons.dart';
import '../../core/theme.dart';
import 'habit_editor.dart';
import 'habits_view_model.dart';

/// One tap anywhere on a habit ticks today. Long-press edits.
class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HabitsViewModel>();
    final c = context.ew;
    final week = vm.week;

    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showHabitEditor(context),
        backgroundColor: c.good,
        foregroundColor: c.onAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New habit'),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: Text('Habits', style: context.type.headlineMedium)),
                  if (vm.loaded && vm.habits.isNotEmpty)
                    Text('${vm.doneToday} of ${vm.habits.length} today', style: context.type.bodySmall),
                ],
              ),
            ),
            if (vm.loaded && vm.habits.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Text('No habits yet. Start with one small one.',
                    style: context.type.bodyLarge?.copyWith(color: c.muted)),
              ),
            for (final h in vm.habits) _HabitCard(status: h, week: week, onTap: () => vm.toggle(h)),
          ],
        ),
      ),
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({required this.status, required this.week, required this.onTap});

  final HabitStatus status;
  final List<String> week;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final done = status.doneToday;
    final h = status.habit;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          onLongPress: () => showHabitEditor(context, habit: h),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: done ? c.good : c.surfaceHigh, shape: BoxShape.circle),
                      child: Icon(
                        done ? Icons.check_rounded : habitIcon(h.icon),
                        color: done ? c.onAccent : c.text,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.name, style: context.type.titleMedium),
                          if (h.reminderTime != null)
                            Text('Reminder ${formatClock(h.reminderTime!)}', style: context.type.bodySmall),
                        ],
                      ),
                    ),
                    _Streak(days: status.streak),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 7; i++)
                      _Dot(
                        label: weekdayShort[LogicalDay.parse(week[i]).weekday - 1].substring(0, 1),
                        done: status.last7[i],
                        isToday: i == 6,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Streak extends StatelessWidget {
  const _Streak({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final hot = days >= 3;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.local_fire_department_rounded, color: hot ? c.warn : c.muted, size: 22),
        const SizedBox(width: 2),
        Text('$days', style: ewText(20, 760, width: 85, color: hot ? c.warn : c.muted)),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.label, required this.done, required this.isToday});

  final String label;
  final bool done;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? c.good : Colors.transparent,
            border: Border.all(color: done ? c.good : (isToday ? c.text : c.surfaceHigh), width: 2),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: context.type.labelSmall?.copyWith(color: isToday ? c.text : c.muted)),
      ],
    );
  }
}
