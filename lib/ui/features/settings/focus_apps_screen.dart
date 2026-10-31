import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories.dart';
import '../../../data/settings_keys.dart';
import '../../app_controller.dart';
import '../../core/theme.dart';

/// Pick which apps focus mode blocks.
class FocusAppsScreen extends StatefulWidget {
  const FocusAppsScreen({super.key});

  @override
  State<FocusAppsScreen> createState() => _FocusAppsScreenState();
}

class _FocusAppsScreenState extends State<FocusAppsScreen> {
  List<({String package, String label})>? _apps;
  late Set<String> _chosen;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    _chosen = app.settings.focusApps.toSet();
    app.bridge.launchableApps().then((list) {
      if (mounted) setState(() => _apps = list);
    });
  }

  Future<void> _toggle(String pkg, bool on) async {
    setState(() => on ? _chosen.add(pkg) : _chosen.remove(pkg));
    await context.read<AppController>().update({
      SettingsKeys.focusApps: SettingsRepository.encodeList(_chosen.toList()),
    });
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    final q = _query.toLowerCase();
    final shown = apps == null
        ? const <({String package, String label})>[]
        : (apps.where((a) => q.isEmpty || a.label.toLowerCase().contains(q)).toList()
          ..sort((a, b) {
            final ca = _chosen.contains(a.package) ? 0 : 1;
            final cb = _chosen.contains(b.package) ? 0 : 1;
            return ca != cb ? ca - cb : a.label.toLowerCase().compareTo(b.label.toLowerCase());
          }));

    return Scaffold(
      appBar: AppBar(title: Text('Blocked apps (${_chosen.length})')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(hintText: 'Search apps', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: apps == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final a = shown[i];
                      return CheckboxListTile(
                        value: _chosen.contains(a.package),
                        onChanged: (v) => _toggle(a.package, v ?? false),
                        title: Text(a.label),
                        subtitle: Text(a.package, style: context.type.bodySmall),
                        activeColor: context.ew.good,
                        checkColor: context.ew.onAccent,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
