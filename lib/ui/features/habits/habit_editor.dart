import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../data/repositories.dart';
import '../../../domain/models.dart';
import '../../core/habit_icons.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';

/// Create or edit a habit: name, icon, optional daily reminder.
Future<void> showHabitEditor(BuildContext context, {Habit? habit}) {
  final repo = context.read<HabitsRepository>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HabitForm(repo: repo, habit: habit, outer: context),
  );
}

class _HabitForm extends StatefulWidget {
  const _HabitForm({required this.repo, required this.habit, required this.outer});

  final HabitsRepository repo;
  final Habit? habit;
  final BuildContext outer;

  @override
  State<_HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends State<_HabitForm> {
  late final _name = TextEditingController(text: widget.habit?.name ?? '');
  late String _icon = widget.habit?.icon ?? 'spark';
  late String? _reminder = widget.habit?.reminderTime;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final p = (_reminder ?? '20:00').split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
    );
    if (t != null) setState(() => _reminder = '${twoDigits(t.hour)}:${twoDigits(t.minute)}');
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop();
    final h = widget.habit;
    if (h == null) {
      await widget.repo.add(name, _icon, _reminder);
    } else {
      await widget.repo.update(h.id, name, _icon, _reminder);
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
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_none_rounded),
              title: const Text('Reminder'),
              subtitle: Text(_reminder == null ? 'Off' : formatClock(_reminder!)),
              trailing: _reminder == null
                  ? null
                  : IconButton(
                      tooltip: 'Remove reminder',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _reminder = null),
                    ),
              onTap: _pickTime,
            ),
            const SizedBox(height: 12),
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
