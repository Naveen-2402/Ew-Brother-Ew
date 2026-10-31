import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories.dart';
import '../../../data/settings_keys.dart';
import '../../app_controller.dart';
import '../../core/theme.dart';

/// Edit the pause-screen lines. One is picked at random for each pause.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  static const defaults = [
    "Ew, brother, ew. What's that? Take 5.",
    'Thambi, podhum da. 5 seconds.',
    'Ugh. Enough. Breathe.',
    'Nopey. Not yet. 5 seconds.',
    'Last one promise? Sure you did. Wait 5.',
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final list = app.settings.messages;
    final c = context.ew;

    Future<void> save(List<String> next) =>
        app.update({SettingsKeys.messages: SettingsRepository.encodeList(next)});

    Future<void> edit({int? index}) async {
      final text = await showDialog<String>(
        context: context,
        builder: (_) => _MessageDialog(initial: index == null ? '' : list[index]),
      );
      if (text == null || text.trim().isEmpty) return;
      final next = [...list];
      if (index == null) {
        next.add(text.trim());
      } else {
        next[index] = text.trim();
      }
      await save(next);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pause messages'),
        actions: [
          TextButton(onPressed: () => save(defaults), child: const Text('Reset')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(),
        backgroundColor: c.good,
        foregroundColor: c.onAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add message'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (var i = 0; i < list.length; i++)
            ListTile(
              title: Text(list[i], style: context.type.bodyLarge),
              onTap: () => edit(index: i),
              trailing: IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.close_rounded),
                onPressed: list.length <= 1 ? null : () => save([...list]..removeAt(i)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageDialog extends StatefulWidget {
  const _MessageDialog({required this.initial});

  final String initial;

  @override
  State<_MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends State<_MessageDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? 'New message' : 'Edit message'),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Thambi, enough da.'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
      ],
    );
  }
}
