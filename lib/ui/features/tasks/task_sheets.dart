import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
      onSubmit: (title, repeat, top) async {
        final starred = await repo.add(title, repeatDaily: repeat, top: top);
        if (!starred && context.mounted) showSnack(context, 'Only 3 can be starred. Added without a star.');
      },
    ),
  );
}

/// Edit title, repeat and star; delete.
Future<void> showTaskEditor(BuildContext context, Task task) {
  final repo = context.read<TasksRepository>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _TaskForm(
      title: 'Edit task',
      submitLabel: 'Save',
      initial: task,
      onSubmit: (title, repeat, top) async {
        await repo.edit(task.id, title: title, repeatDaily: repeat);
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
  final Future<void> Function(String title, bool repeat, bool top) onSubmit;
  final Future<void> Function()? onDelete;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  late final _text = TextEditingController(text: widget.initial?.title ?? '');
  late bool _repeat = widget.initial?.repeatDaily ?? false;
  late bool _top = widget.initial?.isTop3 ?? false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop();
    await widget.onSubmit(t, _repeat, _top);
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
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
          const SizedBox(height: 12),
          Row(
            children: [
              if (widget.onDelete != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: context.ew.bad),
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
    );
  }
}
