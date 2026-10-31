import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../data/app_database.dart';
import '../../../data/settings_keys.dart';
import '../../../domain/models.dart';
import '../../app_controller.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'detection_screen.dart';
import 'focus_apps_screen.dart';
import 'messages_screen.dart';
import 'permissions_screen.dart';
import 'settings_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final s = app.settings;
    final c = context.ew;

    Future<void> pickTime(String key, String current) async {
      final p = current.split(':');
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: int.tryParse(p.first) ?? 8, minute: int.tryParse(p.last) ?? 0),
      );
      if (t != null) await app.update({key: '${twoDigits(t.hour)}:${twoDigits(t.minute)}'});
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          SettingsGroup(
            title: 'Monitoring',
            children: [
              SwitchListTile(
                value: s.monitorOn,
                onChanged: (v) => app.setFlag(SettingsKeys.monitorOn, v),
                title: const Text('Count reels and pause me'),
                subtitle: const Text('Off means nothing is counted, no pause, no bubble'),
              ),
              SwitchListTile(
                value: s.bubbleOn,
                onChanged: (v) => app.setFlag(SettingsKeys.bubbleOn, v),
                title: const Text('Floating counter'),
                subtitle: const Text('Over Instagram and YouTube. Drag it, tap to expand, long-press to hide'),
              ),
              if (s.bubbleOn)
                ChoiceTile<BubbleSize>(
                  title: 'Counter size',
                  value: s.bubbleSize,
                  options: const {BubbleSize.small: 'Small', BubbleSize.medium: 'Medium', BubbleSize.large: 'Large'},
                  onChanged: (v) => app.update({SettingsKeys.bubbleSize: v.name}),
                ),
            ],
          ),
          SettingsGroup(
            title: 'Pause',
            children: [
              SliderTile(
                title: 'Pause every N Instagram Reels',
                value: s.intervalInstagram,
                min: 1,
                max: 100,
                divisions: 99,
                label: (v) => '$v',
                onSaved: (v) => app.update({SettingsKeys.intervalInstagram: '$v'}),
              ),
              SliderTile(
                title: 'Pause every N YouTube Shorts',
                value: s.intervalYoutube,
                min: 1,
                max: 100,
                divisions: 99,
                label: (v) => '$v',
                onSaved: (v) => app.update({SettingsKeys.intervalYoutube: '$v'}),
              ),
              SliderTile(
                title: 'Pause length',
                value: s.pauseSeconds,
                min: 3,
                max: 15,
                divisions: 12,
                label: (v) => '$v sec',
                onSaved: (v) => app.update({SettingsKeys.pauseSeconds: '$v'}),
              ),
              ListTile(
                title: const Text('Pause messages'),
                subtitle: Text('${s.messages.length} messages, picked at random'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _push(context, const MessagesScreen()),
              ),
              ListTile(
                title: const Text('Preview the pause'),
                subtitle: const Text('Shows the real pause screen now'),
                trailing: const Icon(Icons.play_arrow_rounded),
                onTap: () async {
                  final ok = await app.bridge.previewPause();
                  if (!ok && context.mounted) {
                    showSnack(context, 'Turn on the accessibility service first.',
                        action: 'Setup', onAction: () => _push(context, const PermissionsScreen()));
                  }
                },
              ),
            ],
          ),
          SettingsGroup(
            title: 'Daily limit',
            children: [
              SwitchListTile(
                value: s.limitOn,
                onChanged: (v) => app.setFlag(SettingsKeys.limitOn, v),
                title: const Text('Hard limit'),
                subtitle: const Text('Counts Reels and Shorts together'),
              ),
              if (s.limitOn) ...[
                SliderTile(
                  title: 'Limit',
                  value: s.limitReels,
                  min: 20,
                  max: 500,
                  divisions: 48,
                  label: (v) => '$v reels',
                  onSaved: (v) => app.update({SettingsKeys.limitReels: '$v'}),
                ),
                SwitchListTile(
                  value: s.limitAction == LimitAction.block,
                  onChanged: (v) => app.update({
                    SettingsKeys.limitAction: v ? LimitAction.block.name : LimitAction.pause30.name,
                  }),
                  title: const Text('Block reels at the limit'),
                  subtitle: Text(
                    s.limitAction == LimitAction.block
                        ? 'The Reels and Shorts feeds are blocked. Messages and normal videos still work.'
                        : 'Off: a 30-second pause after every reel over the limit.',
                  ),
                ),
              ],
              SliderTile(
                title: 'New day starts at',
                value: s.pendingResetHour ?? s.dayResetHour,
                min: 0,
                max: 23,
                divisions: 23,
                label: formatHour,
                onSaved: app.setResetHour,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  s.pendingResetHour == null
                      ? "Changes apply from the next day, so today's count can't be reset."
                      : 'Today runs until ${formatHour(s.dayResetHour)}. '
                          'From then, a new day starts at ${formatHour(s.pendingResetHour!)}.',
                  style: context.type.bodySmall,
                ),
              ),
            ],
          ),
          SettingsGroup(
            title: 'Interruptions',
            children: [
              SwitchListTile(
                value: s.interruptOn,
                onChanged: (v) => app.setFlag(SettingsKeys.interruptOn, v),
                title: const Text('Ask my goal'),
                subtitle: const Text('5-second "What is your goal?" when opening Instagram or YouTube'),
              ),
              SwitchListTile(
                value: s.focusOn,
                onChanged: (v) => app.setFlag(SettingsKeys.focusOn, v),
                title: const Text('Focus mode'),
                subtitle: Text('Blocks chosen apps from ${formatClock(s.focusStart)} to ${formatClock(s.focusEnd)}'),
              ),
              if (s.focusOn) ...[
                ListTile(
                  title: const Text('Starts'),
                  trailing: Text(formatClock(s.focusStart), style: context.type.labelLarge),
                  onTap: () => pickTime(SettingsKeys.focusStart, s.focusStart),
                ),
                ListTile(
                  title: const Text('Ends'),
                  trailing: Text(formatClock(s.focusEnd), style: context.type.labelLarge),
                  onTap: () => pickTime(SettingsKeys.focusEnd, s.focusEnd),
                ),
                ListTile(
                  title: const Text('Blocked apps'),
                  subtitle: Text(s.focusApps.isEmpty ? 'None chosen yet' : '${s.focusApps.length} apps'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _push(context, const FocusAppsScreen()),
                ),
              ],
            ],
          ),
          SettingsGroup(
            title: 'Reminders',
            children: [
              SwitchListTile(
                value: s.morningOn,
                onChanged: (v) => app.setFlag(SettingsKeys.morningOn, v),
                title: const Text('Morning top 3'),
                subtitle: Text(formatClock(s.morningTime)),
              ),
              if (s.morningOn)
                ListTile(
                  title: const Text('Morning time'),
                  trailing: Text(formatClock(s.morningTime), style: context.type.labelLarge),
                  onTap: () => pickTime(SettingsKeys.morningTime, s.morningTime),
                ),
              SwitchListTile(
                value: s.eveningOn,
                onChanged: (v) => app.setFlag(SettingsKeys.eveningOn, v),
                title: const Text('Evening habit check'),
                subtitle: Text(formatClock(s.eveningTime)),
              ),
              if (s.eveningOn)
                ListTile(
                  title: const Text('Evening time'),
                  trailing: Text(formatClock(s.eveningTime), style: context.type.labelLarge),
                  onTap: () => pickTime(SettingsKeys.eveningTime, s.eveningTime),
                ),
              SwitchListTile(
                value: s.weeklyOn,
                onChanged: (v) => app.setFlag(SettingsKeys.weeklyOn, v),
                title: const Text('Sunday summary'),
                subtitle: const Text('This week against last week, 7 PM'),
              ),
              SwitchListTile(
                value: s.statusNotifOn,
                onChanged: (v) => app.setFlag(SettingsKeys.statusNotifOn, v),
                title: const Text('Status notification'),
                subtitle: const Text('Live count with a pause/resume button'),
              ),
            ],
          ),
          SettingsGroup(
            title: 'Appearance',
            children: [
              ChoiceTile<String>(
                title: 'Theme',
                value: s.theme,
                options: const {'dark': 'Dark', 'light': 'Light', 'system': 'System'},
                onChanged: (v) => app.update({SettingsKeys.theme: v}),
              ),
            ],
          ),
          SettingsGroup(
            title: 'Backup',
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file_rounded),
                title: const Text('Export backup'),
                subtitle: const Text('Saves everything to a file you choose'),
                onTap: () => _export(context),
              ),
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Restore from backup'),
                subtitle: const Text('Replaces all current data'),
                onTap: () => _import(context),
              ),
            ],
          ),
          SettingsGroup(
            title: 'Help',
            children: [
              ListTile(
                leading: Icon(
                  app.permissions.allCore ? Icons.verified_rounded : Icons.error_outline_rounded,
                  color: app.permissions.allCore ? c.good : c.warn,
                ),
                title: const Text('Setup and permissions'),
                subtitle: const Text('Accessibility, usage access, Xiaomi settings'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _push(context, const PermissionsScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.manage_search_rounded),
                title: const Text('Detection check'),
                subtitle: const Text('If counting breaks after an Instagram or YouTube update'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _push(context, const DetectionScreen()),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            child: Text('Ew Brother Ew. Ew, brother, ew. 5 seconds.\nEverything stays on this phone.',
                style: context.type.bodySmall),
          ),
        ],
      ),
    );
  }

  static void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _export(BuildContext context) async {
    final app = context.read<AppController>();
    final now = DateTime.now();
    final name = 'ew-brother-${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}.db';
    // Native flushes the WAL into the main file before copying; our idle connection is fine.
    final result = await app.bridge.exportBackup(name);
    if (!context.mounted) return;
    if (result == 'ok') {
      showSnack(context, 'Backup saved.');
    } else if (result != 'cancelled') {
      showSnack(context, 'Backup failed: ${result.replaceFirst('error: ', '')}');
    }
  }

  Future<void> _import(BuildContext context) async {
    final app = context.read<AppController>();
    final db = context.read<AppDatabase>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text('Everything in the app now is replaced by the backup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    await db.close();
    String result;
    try {
      result = await app.bridge.importBackup();
    } on PlatformException catch (e) {
      result = 'error: ${e.message ?? e.code}';
    } finally {
      // Always reopen, even if the picker failed, or every screen would hit a closed database.
      await app.reopenAfterImport();
    }
    if (!context.mounted) return;
    if (result == 'ok') {
      showSnack(context, 'Restored. Welcome back.');
    } else if (result != 'cancelled') {
      showSnack(context, result.replaceFirst('error: ', ''));
    }
  }
}
