import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../data/repositories.dart';
import '../../../domain/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';

/// Quick add from anywhere (Today's empty state).
Future<void> showQuickAddTask(BuildContext context) {
  final repo = context.read<TasksRepository>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _TaskForm(
      title: 'New task',
      submitLabel: 'Add task',
      onSubmit: (title, repeat, top, remindAt) async {
        final starred = await repo.add(title, repeatDaily: repeat, top: top, remindAt: remindAt);
        if (!starred && context.mounted) showSnack(context, 'Only 3 can be starred. Added without a star.');
      },
    ),
  );
}

/// Edit title, repeat, star and reminder; delete.
Future<void> showTaskEditor(BuildContext context, Task task) {
  final repo = context.read<TasksRepository>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _TaskForm(
      title: 'Edit task',
      submitLabel: 'Save',
      initial: task,
      onSubmit: (title, repeat, top, remindAt) async {
        await repo.edit(task.id, title: title, repeatDaily: repeat, remindAt: remindAt);
        if (top != task.isTop3) {
          final ok = await repo.setTop(task.id, top);
          if (!ok && context.mounted) showSnack(context, 'Only 3 can be starred. Unstar one first.');
        }
      },
      onDelete: () async {
        await repo.delete(task.id);
        if (context.mounted) {
          showSnack(context, 'Task deleted', action: 'Undo', onAction: () => repo.restore(task));
        }
      },
    ),
  );
}

/// Picks a reminder. Daily tasks only need a time; others get a date first.
/// A time already passed today moves to tomorrow (when no date was asked).
Future<DateTime?> pickTaskReminder(BuildContext context, {DateTime? initial, required bool daily}) async {
  final now = DateTime.now();
  final start = initial ?? now.add(const Duration(hours: 1));
  var day = DateTime(now.year, now.month, now.day);
  if (!daily) {
    final picked = await showDatePicker(
      context: context,
      initialDate: start.isBefore(now) ? now : start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !context.mounted) return null;
    day = picked;
  }
  final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: start.hour, minute: start.minute));
  if (t == null) return null;
  var at = DateTime(day.year, day.month, day.day, t.hour, t.minute);
  if (!at.isAfter(now)) {
    if (!daily && day != DateTime(now.year, now.month, now.day)) return at;
    at = at.add(const Duration(days: 1)); // that time has passed today: tomorrow
  }
  return at;
}

class _TaskForm extends StatefulWidget {
  const _TaskForm({
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    this.initial,
    this.onDelete,
  });

  final String title;
  final String submitLabel;
  final Task? initial;
  final Future<void> Function(String title, bool repeat, bool top, DateTime? remindAt) onSubmit;
  final Future<void> Function()? onDelete;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  late final _text = TextEditingController(text: widget.initial?.title ?? '');
  late bool _repeat = widget.initial?.repeatDaily ?? false;
  late bool _top = widget.initial?.isTop3 ?? false;
  late DateTime? _remindAt = widget.initial?.remindAt;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop();
    await widget.onSubmit(t, _repeat, _top, _remindAt);
  }

  Future<void> _pickReminder() async {
    final at = await pickTaskReminder(context, initial: _remindAt, daily: _repeat);
    if (at != null && mounted) setState(() => _remindAt = at);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final past = _remindAt != null && !_repeat && _remindAt!.isBefore(DateTime.now());
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: context.type.headlineSmall),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              autofocus: widget.initial == null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              maxLength: maxTitleLength,
              decoration: const InputDecoration(hintText: 'What needs doing?', counterText: ''),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _repeat,
              onChanged: (v) => setState(() => _repeat = v),
              title: const Text('Repeat daily'),
              subtitle: const Text('Comes back undone every morning'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _top,
              onChanged: (v) => setState(() => _top = v),
              title: const Text('In my top 3'),
              subtitle: const Text('Shown on Today and on the pause screen'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _remindAt == null ? Icons.notifications_none_rounded : Icons.notifications_active_outlined,
                color: _remindAt == null ? null : c.warn,
              ),
              title: const Text('Reminder'),
              subtitle: Text(
                _remindAt == null
                    ? 'Off'
                    : past
                        ? '${formatReminder(_remindAt!, daily: false)} (passed)'
                        : formatReminder(_remindAt!, daily: _repeat),
                style: past ? TextStyle(color: c.muted) : null,
              ),
              trailing: _remindAt == null
                  ? null
                  : IconButton(
                      tooltip: 'Remove reminder',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _remindAt = null),
                    ),
              onTap: _pickReminder,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.onDelete != null)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: c.bad),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await widget.onDelete!();
                    },
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
