import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../domain/models.dart';
import '../../../domain/score.dart';
import '../../app.dart';
import '../../app_controller.dart';
import '../../core/habit_icons.dart';
import '../../core/theme.dart';
import '../../core/widgets/brain_mood.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/mascot.dart';
import '../habits/habit_editor.dart';
import '../settings/permissions_screen.dart';
import '../settings/settings_screen.dart';
import '../tasks/task_sheets.dart';
import 'today_view_model.dart';

/// Answers three questions at a glance: how much did I scroll, what must I do,
/// and which habits are left. Scroll info on top (glance), actions in the bottom half (thumb).
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TodayViewModel>();
    final perms = context.select<AppController, bool>((a) => a.permissions.counting);
    final now = DateTime.now();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: vm.load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  const Mascot(size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${weekdayLong[now.weekday - 1]}, ${now.day} ${monthLong[now.month - 1]}',
                      style: context.type.titleSmall,
                    ),
                  ),
                  _MonitorPill(vm: vm),
                  IconButton(
                    tooltip: 'Settings',
                    iconSize: 26,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
            if (!perms) const _SetupBanner(),
            FadeSlideIn(child: _ReelBlock(vm: vm)),
            FadeSlideIn(index: 1, child: _Figures(vm: vm)),
            SectionTitle(
              'Top 3 today',
              trailing: TextButton(
                onPressed: () => context.read<TabIndex>().value = 1,
                child: const Text('All tasks'),
              ),
            ),
            if (vm.loaded && vm.top.isEmpty)
              EmptyState(line: 'No tasks yet.', action: 'Add a task', onPressed: () => showQuickAddTask(context))
            else
              for (final (i, t) in vm.top.indexed)
                FadeSlideIn(key: ValueKey('top-${t.id}'), index: 2 + i, child: _TaskRow(task: t, onTap: () => vm.toggleTask(t))),
            SectionTitle(
              'Habits',
              trailing: TextButton(
                onPressed: () => context.read<TabIndex>().value = 2,
                child: const Text('All habits'),
              ),
            ),
            if (vm.loaded && vm.habitList.isEmpty)
              EmptyState(line: 'No habits yet.', action: 'Add a habit', onPressed: () => showHabitEditor(context))
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final h in vm.habitList) _HabitChip(status: h, onTap: () => vm.toggleHabit(h))],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner();

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      decoration: BoxDecoration(
        color: c.warn.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('Reel counting is off until setup is done.', style: context.type.bodyMedium),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.warn, foregroundColor: c.onAccent),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PermissionsScreen()),
            ),
            child: const Text('Finish setup'),
          ),
        ],
      ),
    );
  }
}

/// The one loud element: today's reel count, coloured by how close the limit is.
class _ReelBlock extends StatelessWidget {
  const _ReelBlock({required this.vm});

  final TodayViewModel vm;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final s = vm.settings;
    final total = vm.reelDay.total;
    final color = c.progress(total, s.softLimit);
    final ratio = (total / s.softLimit).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                child: Text(
                  '$total',
                  key: ValueKey(total),
                  style: context.type.displayLarge?.copyWith(color: color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('reels today', style: context.type.titleMedium),
                      Text(moodLine(vm.mood), style: context.type.bodySmall),
                    ],
                  ),
                ),
              ),
              BrainMoodIcon(mood: vm.mood, size: 76),
            ],
          ),
          const SizedBox(height: 18),
          TweenAnimationBuilder<double>(
            tween: Tween(end: ratio),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => CustomPaint(
              size: const Size(double.infinity, 18),
              painter: _TickRulerPainter(value: v, fill: color, empty: c.surfaceHigh),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _AppCount(color: c.insta, label: 'Reels', value: vm.reelDay.instagram),
              const SizedBox(width: 18),
              _AppCount(color: c.shorts, label: 'Shorts', value: vm.reelDay.youtube),
              const Spacer(),
              Text(
                s.limitOn ? 'limit ${s.limitReels}' : 'no limit',
                style: context.type.labelMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Progress drawn as a row of ticks, like a ruler filling up. Every 5th tick is taller.
class _TickRulerPainter extends CustomPainter {
  _TickRulerPainter({required this.value, required this.fill, required this.empty});

  final double value;
  final Color fill;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    const tick = 3.0;
    const minGap = 4.0;
    final count = ((size.width + minGap) / (tick + minGap)).floor().clamp(10, 80);
    final gap = (size.width - count * tick) / (count - 1);
    final lit = (value * count).round();
    for (var i = 0; i < count; i++) {
      final major = i % 5 == 4;
      final h = major ? size.height : size.height * 0.62;
      final x = i * (tick + gap);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h, tick, h),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(r, Paint()..color = i < lit ? fill : empty);
    }
  }

  @override
  bool shouldRepaint(_TickRulerPainter old) => old.value != value || old.fill != fill || old.empty != empty;
}

class _AppCount extends StatelessWidget {
  const _AppCount({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label ', style: context.type.labelMedium),
        Text('$value', style: context.type.labelLarge),
      ],
    );
  }
}

/// Small on/off pill in the header. Replaces the big monitoring card.
class _MonitorPill extends StatelessWidget {
  const _MonitorPill({required this.vm});

  final TodayViewModel vm;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final on = vm.settings.monitorOn;
    final tone = on ? c.good : c.warn;
    return Semantics(
      button: true,
      toggled: on,
      label: on ? 'Monitoring on. Tap to pause.' : 'Monitoring paused. Tap to resume.',
      excludeSemantics: true,
      child: SizedBox(
        height: 48,
        child: Center(
          child: Material(
            color: tone.withValues(alpha: 0.12),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => vm.setMonitor(!on),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(on ? 'Watching' : 'Paused', style: context.type.labelMedium?.copyWith(color: tone)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three figures in a ruled row, no card: score, screen time, what's left.
class _Figures extends StatelessWidget {
  const _Figures({required this.vm});

  final TodayViewModel vm;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final s = vm.settings;
    final score = vm.score;
    final scoreColor = score >= 70 ? c.good : (score >= 40 ? c.warn : c.bad);
    final left = s.limitReels - vm.reelDay.total;
    Widget rule() => Container(width: 1, height: 34, color: c.surfaceHigh);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: c.surfaceHigh)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Figure(
              lead: true,
              value: '$score',
              unit: '/100',
              label: 'day score',
              color: scoreColor,
            ),
          ),
          rule(),
          Expanded(child: _Figure(value: formatDuration(vm.screenSeconds), label: 'screen time')),
          rule(),
          Expanded(
            child: s.limitOn
                ? _Figure(
                    value: left > 0 ? '$left' : '0',
                    label: left > 0 ? 'reels left' : 'limit hit',
                    color: left > 0 ? null : c.bad,
                  )
                : _Figure(value: formatDuration(vm.reelDay.seconds), label: 'on reels'),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, this.unit, this.color, this.lead = false});

  /// First figure sits on the page margin; the others get room after the rule.
  final bool lead;
  final String value;
  final String label;
  final String? unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Padding(
      padding: EdgeInsets.only(left: lead ? 0 : 14, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: value,
              style: ewText(24, 760, width: 82, color: color ?? c.text, height: 1.1),
              children: [
                if (unit != null) TextSpan(text: unit, style: ewText(12, 560, color: c.muted)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
          ),
          const SizedBox(height: 2),
          Text(label, style: context.type.bodySmall, maxLines: 1),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onTap});

  final Task task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            CheckDot(done: task.isDone, onTap: onTap),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: context.type.bodyLarge!.copyWith(
                  color: task.isDone ? c.muted : c.text,
                  decoration: task.isDone ? TextDecoration.lineThrough : null,
                  decorationColor: c.muted,
                ),
                child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (task.repeatDaily)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.repeat_rounded, size: 18, color: c.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _HabitChip extends StatelessWidget {
  const _HabitChip({required this.status, required this.onTap});

  final HabitStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final done = status.doneToday;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: done ? c.good.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: done ? c.good.withValues(alpha: 0.55) : c.surfaceHigh, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                done ? Icons.check_rounded : habitIcon(status.habit.icon),
                size: 19,
                color: done ? c.good : c.muted,
              ),
              const SizedBox(width: 8),
              Text(
                status.habit.name,
                style: context.type.labelLarge?.copyWith(color: done ? c.muted : c.text),
              ),
              if (status.streak > 1) ...[
                const SizedBox(width: 8),
                Text('${status.streak}', style: ewText(15, 760, width: 80, color: c.warn)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
