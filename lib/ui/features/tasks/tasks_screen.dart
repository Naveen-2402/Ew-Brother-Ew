import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'task_sheets.dart';
import 'tasks_view_model.dart';

/// Swipe right to complete, swipe left to delete, long-press and drag to reorder,
/// tap to edit. The quick-add bar sits at the bottom for one-handed use.
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TasksViewModel>();
    final c = context.ew;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: Text('Tasks', style: context.type.headlineMedium)),
                if (vm.loaded)
                  Text(
                    vm.open.isEmpty ? 'All clear' : '${vm.open.length} open, ${vm.starred} of 3 starred',
                    style: context.type.bodySmall,
                  ),
              ],
            ),
          ),
          Expanded(
            child: vm.loaded && vm.open.isEmpty && vm.doneToday.isEmpty
                ? Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('Nothing to do. Suspicious.', style: context.type.bodyLarge?.copyWith(color: c.muted)),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    itemCount: vm.open.length,
                    onReorderItem: vm.reorder,
                    proxyDecorator: (child, _, _) => Material(
                      color: c.surfaceHigh,
                      elevation: 6,
                      borderRadius: BorderRadius.circular(16),
                      child: child,
                    ),
                    itemBuilder: (context, i) {
                      final t = vm.open[i];
                      return FadeSlideIn(
                        key: ValueKey(t.id),
                        index: i,
                        child: _SwipeTask(task: t, vm: vm),
                      );
                    },
                    footer: vm.doneToday.isEmpty
                        ? null
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionTitle('Done today'),
                              for (final t in vm.doneToday)
                                _TaskTile(
                                  task: t,
                                  onCheck: () => vm.reopen(t),
                                  onTap: () => showTaskEditor(context, t),
                                ),
                            ],
                          ),
                  ),
          ),
          _QuickAddBar(vm: vm),
        ],
      ),
    );
  }
}

class _SwipeTask extends StatelessWidget {
  const _SwipeTask({required this.task, required this.vm});

  final Task task;
  final TasksViewModel vm;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Dismissible(
      key: ValueKey('swipe-${task.id}'),
      background: _SwipeBg(color: c.good, icon: Icons.check_rounded, alignEnd: false, label: 'Done'),
      secondaryBackground: _SwipeBg(color: c.bad, icon: Icons.delete_outline_rounded, alignEnd: true, label: 'Delete'),
      onDismissed: (dir) {
        if (dir == DismissDirection.startToEnd) {
          vm.complete(task);
          showSnack(context, 'Done. Look at you.', action: 'Undo', onAction: () => vm.reopen(task));
        } else {
          vm.delete(task);
          showSnack(context, 'Task deleted', action: 'Undo', onAction: () => vm.restore(task));
        }
      },
      child: _TaskTile(
        task: task,
        onCheck: () {
          vm.complete(task);
          showSnack(context, 'Done. Look at you.', action: 'Undo', onAction: () => vm.reopen(task));
        },
        onTap: () => showTaskEditor(context, task),
        trailing: IconButton(
          tooltip: task.isTop3 ? 'Remove from top 3' : 'Add to top 3',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              task.isTop3 ? Icons.star_rounded : Icons.star_outline_rounded,
              key: ValueKey(task.isTop3),
              color: task.isTop3 ? c.warn : c.muted,
            ),
          ),
          onPressed: () async {
            final ok = await vm.toggleTop(task);
            if (!ok && context.mounted) showSnack(context, 'Only 3 can be starred. Unstar one first.');
          },
        ),
      ),
    );
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({required this.color, required this.icon, required this.alignEnd, required this.label});

  final Color color;
  final IconData icon;
  final bool alignEnd;
  final String label;

  @override
  Widget build(BuildContext context) {
    final on = context.ew.onAccent;
    final children = [
      Icon(icon, color: on),
      const SizedBox(width: 8),
      Text(label, style: context.type.labelLarge?.copyWith(color: on)),
    ];
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignEnd ? children.reversed.toList() : children,
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onCheck, required this.onTap, this.trailing});

  final Task task;
  final VoidCallback onCheck;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Row(
              children: [
                CheckDot(done: task.isDone, onTap: onCheck),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.bodyLarge?.copyWith(
                          color: task.isDone ? c.muted : c.text,
                          decoration: task.isDone ? TextDecoration.lineThrough : null,
                          decorationColor: c.muted,
                        ),
                      ),
                      if (task.repeatDaily)
                        Row(
                          children: [
                            Icon(Icons.repeat_rounded, size: 14, color: c.muted),
                            const SizedBox(width: 4),
                            Text('Daily', style: context.type.bodySmall),
                          ],
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAddBar extends StatefulWidget {
  const _QuickAddBar({required this.vm});

  final TasksViewModel vm;

  @override
  State<_QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<_QuickAddBar> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _repeat = false;
  bool _top = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    final starred = await widget.vm.add(t, repeat: _repeat, top: _top);
    if (!mounted) return;
    tickHaptic();
    if (!starred) showSnack(context, 'Only 3 can be starred. Added without a star.');
    setState(() => _top = false);
    _focus.requestFocus(); // keep the keyboard up for the next one
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.surfaceHigh)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 2, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  style: context.type.bodyLarge,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _add(),
                  maxLength: maxTitleLength,
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: 'Add a task',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              TextButton(onPressed: _add, child: const Text('Add')),
            ],
          ),
          Row(
            children: [
              _Flag(
                label: 'Repeat daily',
                on: _repeat,
                color: c.good,
                onTap: () => setState(() => _repeat = !_repeat),
              ),
              const SizedBox(width: 8),
              _Flag(
                label: 'Top 3',
                on: _top,
                color: c.warn,
                onTap: () => setState(() => _top = !_top),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small toggle for the quick-add bar. Outlined when off, tinted when on.
class _Flag extends StatelessWidget {
  const _Flag({required this.label, required this.on, required this.color, required this.onTap});

  final String label;
  final bool on;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Semantics(
      button: true,
      toggled: on,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? color.withValues(alpha: 0.6) : c.surfaceHigh, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (on) ...[
                Icon(Icons.check_rounded, size: 16, color: color),
                const SizedBox(width: 4),
              ],
              Text(label, style: context.type.labelMedium?.copyWith(color: on ? color : c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
