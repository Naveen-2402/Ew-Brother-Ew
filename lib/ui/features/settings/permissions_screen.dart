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
            body: 'Morning top 3, evening habits, reminders and the monitor switch.',
            // Once allowed, the button opens the notification settings (to turn them off or tune them).
            action: p.notifications ? 'Open' : 'Allow',
            onAction: () async {
              if (p.notifications) {
                await b.openNotificationSettings();
              } else {
                await b.requestNotifications();
              }
              await app.refreshPermissions();
            },
          ),
          FutureBuilder<String>(
            future: _family ??= b.deviceFamily(),
            builder: (context, snap) {
              final family = snap.data ?? 'other';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BatteryStep(
                    unrestricted: p.battery,
                    // Xiaomi names the modes like this; stock Android, Samsung and most others
                    // say Unrestricted / Optimized under App info > Battery.
                    labels: family == 'xiaomi'
                        ? ('No restrictions', 'Battery saver')
                        : ('Unrestricted', 'Optimized'),
                    onPick: (unrestricted) => b.openBattery(unrestricted: unrestricted),
                  ),
                  ..._extras(context, family, b.openAutostart, b.openAppDetails),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Looked up once per app run: the phone maker doesn't change.
  static Future<String>? _family;

  /// Extra switches some phone makers add on top of Android. They can't be read by apps,
  /// so they're shown as a checklist. Stock Android (Pixel, Motorola, ...) needs none.
  static List<Widget> _extras(
    BuildContext context,
    String family,
    VoidCallback openAutostart,
    VoidCallback openAppDetails,
  ) {
    const lockRecents = _Step(
      title: 'Lock in recents',
      body: 'Open recent apps, long-press (or pull down) the Ew Brother Ew card and tap the lock, '
          'so clearing recents doesn\'t close the counter.',
    );
    final steps = switch (family) {
      'xiaomi' => [
          _Step(
            title: 'Autostart',
            body: 'Lets the counter come back after a restart.',
            action: 'Open',
            onAction: openAutostart,
          ),
          _Step(
            title: 'Pop-up windows in background',
            body: 'App info, Other permissions, allow "Display pop-up windows while running in the background".',
            action: 'App info',
            onAction: openAppDetails,
          ),
          lockRecents,
        ],
      'samsung' => [
          _Step(
            title: 'Never sleeping apps',
            body: 'Settings, Battery, Background usage limits, Never sleeping apps: add Ew Brother Ew. '
                'Also turn off "Put unused apps to sleep" there if it\'s on.',
            action: 'App info',
            onAction: openAppDetails,
          ),
        ],
      'oppo' => [
          _Step(
            title: 'Auto launch',
            body: 'Allow Ew Brother Ew to auto launch, so the counter comes back after a restart.',
            action: 'Open',
            onAction: openAutostart,
          ),
          lockRecents,
        ],
      'vivo' => [
          _Step(
            title: 'Autostart / background start',
            body: 'Allow Ew Brother Ew to start in the background, so the counter comes back after a restart.',
            action: 'Open',
            onAction: openAutostart,
          ),
          lockRecents,
        ],
      'huawei' => [
          _Step(
            title: 'App launch',
            body: 'Set Ew Brother Ew to "Manage manually" and allow auto-launch, secondary launch '
                'and run in background.',
            action: 'Open',
            onAction: openAutostart,
          ),
          lockRecents,
        ],
      _ => const <Widget>[],
    };
    if (steps.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 4),
        child: Text('Phone extras', style: context.type.titleLarge),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(
          'Your phone adds its own background limits. Apps can\'t see these switches, so check them once.',
          style: context.type.bodySmall,
        ),
      ),
      ...steps,
    ];
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.body, this.done, this.action, this.onAction, this.extra});

  /// null = status unknown (a phone maker's own switch apps can't read).
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
              // The button stays after the step is done, so the setting can be changed or turned off.
              if (action != null) ...[
                const SizedBox(width: 8),
                done == true
                    ? OutlinedButton(onPressed: onAction, child: Text(action!))
                    : FilledButton.tonal(onPressed: onAction, child: Text(action!)),
              ],
            ],
          ),
          ?extra,
        ],
      ),
    );
  }
}

/// Battery mode as two choices. The highlighted one is what Android reports right now;
/// tapping either opens the system page to switch (apps can't change it themselves).
class _BatteryStep extends StatelessWidget {
  const _BatteryStep({required this.unrestricted, required this.labels, required this.onPick});

  final bool unrestricted;

  /// (unrestricted, restricted) in the phone's own words.
  final (String, String) labels;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                unrestricted ? Icons.check_circle_rounded : Icons.battery_saver_rounded,
                color: unrestricted ? c.good : c.warn,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Battery', style: context.type.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      unrestricted
                          ? '${labels.$1}: the counter keeps running in the background.'
                          : '${labels.$2}: the phone may stop the counter in the background.',
                      style: context.type.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: true, label: Text(labels.$1), icon: const Icon(Icons.bolt_rounded)),
                ButtonSegment(value: false, label: Text(labels.$2), icon: const Icon(Icons.eco_outlined)),
              ],
              selected: {unrestricted},
              // Tapping the selected one too: opens the page so it can be checked or changed.
              emptySelectionAllowed: true,
              onSelectionChanged: (s) => onPick(s.isEmpty ? unrestricted : s.first),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Opens the system page (on most phones: App info, Battery). Pick the same option there; '
            'this screen updates when you come back.',
            style: context.type.bodySmall,
          ),
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
