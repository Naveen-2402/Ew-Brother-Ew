import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_controller.dart';
import '../../core/theme.dart';
import '../../core/widgets/mascot.dart';

/// Setup checklist. Statuses refresh automatically when you come back from Android settings.
class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final p = app.permissions;
    final b = app.bridge;

    return Scaffold(
      appBar: AppBar(title: const Text('Setup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                const Mascot(size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    p.allCore ? 'All set. Go live your life.' : 'Four switches and Ew Brother starts watching your back.',
                    style: context.type.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
          _Step(
            done: p.counting,
            title: 'Accessibility service',
            body: p.accessibility && !p.serviceRunning
                ? 'Turned on but not running. Turn it off and on again.'
                : 'Counts reels and shows the pause. Open, tap "Ew Brother Ew reel counter", turn it on.',
            action: 'Open',
            onAction: b.openAccessibility,
            extra: p.counting
                ? null
                : _Note(
                    text: 'Greyed out or "Restricted setting"? Open App info, tap the three dots at the top right, '
                        'choose "Allow restricted settings", then come back.',
                    action: 'Open App info',
                    onAction: b.openAppDetails,
                  ),
          ),
          _Step(
            done: p.usage,
            title: 'Usage access',
            body: 'For screen time per app. Find Ew Brother Ew and allow it.',
            action: 'Open',
            onAction: b.openUsageAccess,
          ),
          _Step(
            done: p.notifications,
            title: 'Notifications',
            body: 'Morning top 3, evening habits and the monitor switch.',
            action: 'Allow',
            onAction: () async {
              await b.requestNotifications();
              await app.refreshPermissions();
            },
          ),
          _Step(
            done: p.battery,
            title: 'No battery restrictions',
            body: 'Stops HyperOS from killing the counter in the background.',
            action: 'Open',
            onAction: b.openBattery,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 4),
            child: Text('Xiaomi extras', style: context.type.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('HyperOS can\'t tell us if these are on, so check them once.', style: context.type.bodySmall),
          ),
          _Step(
            title: 'Autostart',
            body: 'Lets the counter come back after a restart.',
            action: 'Open',
            onAction: b.openAutostart,
          ),
          _Step(
            title: 'Battery saver: No restrictions',
            body: 'App info, Battery saver, No restrictions.',
            action: 'App info',
            onAction: b.openAppDetails,
          ),
          _Step(
            title: 'Pop-up windows in background',
            body: 'App info, Other permissions, allow "Display pop-up windows while running in the background".',
            action: 'App info',
            onAction: b.openAppDetails,
          ),
          const _Step(
            title: 'Lock in recents',
            body: 'Open recent apps, long-press the Ew Brother Ew card, tap the lock.',
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.body, this.done, this.action, this.onAction, this.extra});

  /// null = status unknown (manual Xiaomi step).
  final bool? done;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final icon = switch (done) {
      true => Icon(Icons.check_circle_rounded, color: c.good, size: 28),
      false => Icon(Icons.radio_button_unchecked_rounded, color: c.warn, size: 28),
      null => Icon(Icons.phone_android_rounded, color: c.muted, size: 26),
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.type.titleMedium),
                    const SizedBox(height: 2),
                    Text(body, style: context.type.bodySmall),
                  ],
                ),
              ),
              if (action != null && done != true) ...[
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: onAction, child: Text(action!)),
              ],
            ],
          ),
          ?extra,
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.action, required this.onAction});

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 40, top: 10),
      child: Row(
        children: [
          Expanded(child: Text(text, style: context.type.bodySmall?.copyWith(color: context.ew.warn))),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}
