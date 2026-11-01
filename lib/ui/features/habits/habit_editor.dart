import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../data/repositories.dart';
import '../../../domain/models.dart';
import '../../app_controller.dart';
import '../../core/habit_icons.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';

/// Create or edit a habit: name, icon, times per day, reminders (off, once, or repeating
/// every N minutes within a time range).
Future<void> showHabitEditor(BuildContext context, {Habit? habit}) {
  final repo = context.read<HabitsRepository>();
  final app = context.read<AppController>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HabitForm(repo: repo, app: app, habit: habit, outer: context),
  );
}

enum _RemindMode { off, once, range }

/// Minutes between interval reminders. 15 is the floor: Android may delay closer alarms anyway.
const _everyChoices = [15, 30, 45, 60, 90, 120, 180];

String _everyLabel(int m) => m < 60 ? '$m min' : (m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60}');

class _HabitForm extends StatefulWidget {
  const _HabitForm({required this.repo, required this.app, required this.habit, required this.outer});

  final HabitsRepository repo;
  final AppController app;
  final Habit? habit;
  final BuildContext outer;

  @override
  State<_HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends State<_HabitForm> {
  late final _name = TextEditingController(text: widget.habit?.name ?? '');
  late String _icon = widget.habit?.icon ?? 'spark';
  late int _target = widget.habit?.target ?? 1;
  late _RemindMode _mode = switch (widget.habit) {
    null => _RemindMode.off,
    Habit h when h.interval => _RemindMode.range,
    Habit h when h.reminderTime != null => _RemindMode.once,
    _ => _RemindMode.off,
  };
  late String _at = widget.habit?.reminderTime ?? '20:00';
  late String _from = widget.habit?.reminderTime ?? '09:00';
  late String _until = widget.habit?.remindUntil ?? '21:00';
  late int _every = _everyChoices.contains(widget.habit?.remindEvery) ? widget.habit!.remindEvery : 60;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  int _minutes(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  bool get _rangeValid => _minutes(_until) > _minutes(_from);

  /// How many reminders the range gives (shown under the range so the setup is obvious).
  int get _slots => _rangeValid ? (_minutes(_until) - _minutes(_from)) ~/ _every + 1 : 0;

  Future<String?> _pick(String current) async {
    final p = current.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
    );
    return t == null ? null : '${twoDigits(t.hour)}:${twoDigits(t.minute)}';
  }

  HabitPlan get _plan => switch (_mode) {
        _RemindMode.off => HabitPlan(target: _target),
        _RemindMode.once => HabitPlan(target: _target, reminder: _at),
        _RemindMode.range => HabitPlan(target: _target, reminder: _from, every: _every, until: _until),
      };

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (_mode == _RemindMode.range && !_rangeValid) {
      showSnack(context, 'The reminder range has to end after it starts.');
      return;
    }
    Navigator.of(context).pop();
    final h = widget.habit;
    if (h == null) {
      await widget.repo.add(name, _icon, _plan);
    } else {
      await widget.repo.update(h.id, name, _icon, _plan, today: widget.app.today);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.habit == null ? 'New habit' : 'Edit habit', style: context.type.headlineSmall),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.habit == null,
              textCapitalization: TextCapitalization.sentences,
              maxLength: maxTitleLength,
              decoration: const InputDecoration(hintText: 'Drink water, walk, read 10 pages', counterText: ''),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in habitIcons.entries)
                  InkResponse(
                    onTap: () => setState(() => _icon = e.key),
                    radius: 26,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _icon == e.key ? c.good : c.surfaceHigh,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(e.value, color: _icon == e.key ? c.onAccent : c.text, size: 22),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // ---- times per day
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Times a day', style: context.type.titleMedium),
                      Text(
                        _target == 1
                            ? 'Once: one tap ticks it.'
                            : 'Each tap adds one. Done at $_target, whenever you do them.',
                        style: context.type.bodySmall,
                      ),
                    ],
                  ),
                ),
                _Stepper(
                  value: _target,
                  min: 1,
                  max: 30,
                  onChanged: (v) => setState(() => _target = v),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // ---- reminders
            Text('Reminder', style: context.type.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<_RemindMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _RemindMode.off, label: Text('Off')),
                ButtonSegment(value: _RemindMode.once, label: Text('Once')),
                ButtonSegment(value: _RemindMode.range, label: Text('Repeat')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: switch (_mode) {
                _RemindMode.off => const SizedBox(width: double.infinity),
                _RemindMode.once => _TimeRow(
                    label: 'At',
                    value: _at,
                    onTap: () async {
                      final v = await _pick(_at);
                      if (v != null) setState(() => _at = v);
                    },
                  ),
                _RemindMode.range => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _TimeRow(
                              label: 'From',
                              value: _from,
                              onTap: () async {
                                final v = await _pick(_from);
                                if (v != null) setState(() => _from = v);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TimeRow(
                              label: 'To',
                              value: _until,
                              onTap: () async {
                                final v = await _pick(_until);
                                if (v != null) setState(() => _until = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Every', style: context.type.labelMedium),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final m in _everyChoices)
                            ChoiceChip(
                              label: Text(_everyLabel(m)),
                              selected: _every == m,
                              onSelected: (_) => setState(() => _every = m),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _rangeValid
                            ? '$_slots reminders a day. Skipped when you\'re on track, '
                                'and they stop once it\'s done.'
                            : 'The range has to end after it starts.',
                        style: context.type.bodySmall?.copyWith(color: _rangeValid ? null : c.bad),
                      ),
                    ],
                  ),
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.habit != null)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: c.bad),
                    onPressed: () async {
                      final outer = widget.outer;
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text('Delete this habit?'),
                          content: const Text('Its streak and history go too.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: c.bad),
                              onPressed: () => Navigator.pop(d, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (ok != true || !context.mounted) return;
                      Navigator.of(context).pop();
                      await widget.repo.delete(widget.habit!.id);
                      if (outer.mounted) showSnack(outer, 'Habit deleted');
                    },
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: Text(widget.habit == null ? 'Add habit' : 'Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled time you tap to change.
class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Text(label, style: context.type.labelMedium),
                const Spacer(),
                Text(formatClock(value), style: context.type.titleMedium),
                const SizedBox(width: 6),
                Icon(Icons.schedule_rounded, size: 18, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// − value + with 48 dp targets.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged});

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Container(
      decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Fewer',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: ewText(18, 760, width: 82, color: c.text),
            ),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}
