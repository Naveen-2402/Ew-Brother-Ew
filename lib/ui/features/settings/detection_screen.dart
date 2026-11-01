import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories.dart';
import '../../../data/settings_keys.dart';
import '../../app_controller.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';

/// Shows the scroll containers the service saw in Instagram/YouTube, so a new view ID
/// can be added without rebuilding when an app update breaks counting.
class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  List<({String app, String id, bool matched})> _seen = const [];
  List<String> _live = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final bridge = context.read<AppController>().bridge;
    final lines = await bridge.detectionLog();
    final live = await bridge.debugLog();
    if (!mounted) return;
    setState(() {
      _live = live;
      _seen = [
        for (final l in lines)
          if (l.split('|').length == 3)
            (app: l.split('|')[0], id: l.split('|')[1], matched: l.split('|')[2] == '1'),
      ];
    });
  }

  Future<void> _setExtra(List<String> ids) =>
      context.read<AppController>().update({SettingsKeys.extraReelIds: SettingsRepository.encodeList(ids)});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final extra = app.settings.extraReelIds;
    final c = context.ew;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detection check'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'Scroll a few reels in Instagram or YouTube, come back and refresh. '
                'Green rows are counted. If the reel feed shows grey, tap "Count this".',
                style: context.type.bodyMedium?.copyWith(color: c.muted),
              ),
            ),
            const SectionTitle('Seen recently'),
            if (_seen.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  app.permissions.counting ? 'Nothing yet.' : 'The accessibility service is off.',
                  style: context.type.bodyMedium,
                ),
              ),
            for (final s in _seen)
              ListTile(
                leading: Icon(
                  s.matched ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: s.matched ? c.good : c.muted,
                ),
                title: Text(s.id, style: context.type.bodyMedium),
                subtitle: Text(s.app),
                trailing: s.matched || s.id.startsWith('(no id)') || extra.contains(s.id)
                    ? null
                    : TextButton(
                        onPressed: () => _setExtra([...extra, s.id]),
                        child: const Text('Count this'),
                      ),
              ),
            const SectionTitle('Extra IDs you added'),
            if (extra.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('None.', style: context.type.bodyMedium),
              ),
            for (final id in extra)
              ListTile(
                title: Text(id, style: context.type.bodyMedium),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => _setExtra([...extra]..remove(id)),
                ),
              ),
            SectionTitle(
              'Live log',
              trailing: _live.isEmpty
                  ? null
                  : TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _live.join('\n')));
                        if (context.mounted) showSnack(context, 'Log copied');
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy'),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Newest first: app switches, the "What is your goal?" screen, and how each YouTube Short '
                'was counted. If counting goes wrong, refresh and copy this.',
                style: context.type.bodySmall,
              ),
            ),
            if (_live.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Nothing yet.', style: context.type.bodyMedium),
              )
            else
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14)),
                child: SelectableText(
                  _live.join('\n'),
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.45, color: c.text),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
