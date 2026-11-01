import 'dart:async';

import 'package:flutter/services.dart';

/// Permission state reported by the native side.
class PermissionState {
  const PermissionState({
    required this.accessibility,
    required this.serviceRunning,
    required this.usage,
    required this.notifications,
    required this.battery,
  });

  const PermissionState.unknown()
      : accessibility = false,
        serviceRunning = false,
        usage = false,
        notifications = false,
        battery = false;

  final bool accessibility;
  final bool serviceRunning;
  final bool usage;
  final bool notifications;
  final bool battery;

  bool get counting => accessibility && serviceRunning;
  bool get allCore => counting && usage && notifications;
}

/// Wrapper around the "ew/native" MethodChannel. Method names MUST match MainActivity.kt.
class NativeBridge {
  NativeBridge() {
    _channel.setMethodCallHandler((call) async {
      _events.add(call.method);
      return null;
    });
  }

  static const _channel = MethodChannel('ew/native');
  final _events = StreamController<String>.broadcast();

  /// "reelCounted", "dataChanged", "settingsChanged", "serviceChanged".
  Stream<String> get events => _events.stream;

  Future<String> dbPath() async {
    final path = await _channel.invokeMethod<String>('dbPath');
    if (path == null) throw StateError('The database path is not available');
    return path;
  }

  Future<PermissionState> permissions() async {
    try {
      final m = await _channel.invokeMapMethod<String, bool>('permissions') ?? {};
      return PermissionState(
        accessibility: m['accessibility'] ?? false,
        serviceRunning: m['serviceRunning'] ?? false,
        usage: m['usage'] ?? false,
        notifications: m['notifications'] ?? false,
        battery: m['battery'] ?? false,
      );
    } on PlatformException {
      return const PermissionState.unknown();
    }
  }

  Future<void> openAccessibility() => _call('openAccessibility');
  Future<void> openUsageAccess() => _call('openUsageAccess');
  Future<void> requestNotifications() => _call('requestNotifications');
  Future<void> openNotificationSettings() => _call('openNotificationSettings');

  /// Phone maker group: "xiaomi", "samsung", "oppo" (also Realme/OnePlus), "vivo",
  /// "huawei" (also Honor) or "other" (stock Android: Pixel, Motorola, Nokia, ...).
  Future<String> deviceFamily() async {
    try {
      return await _channel.invokeMethod<String>('deviceFamily') ?? 'other';
    } on PlatformException {
      return 'other';
    }
  }

  /// [unrestricted]: ask for "No restrictions". false: open the page to pick "Battery saver".
  Future<void> openBattery({bool unrestricted = true}) =>
      _call('openBattery', {'mode': unrestricted ? 'unrestricted' : 'saver'});
  Future<void> openAutostart() => _call('openAutostart');
  Future<void> openAppDetails() => _call('openAppDetails');

  /// Tell the service, alarms, widget and status notification that settings changed.
  Future<void> settingsChanged() => _call('settingsChanged');

  /// Tasks/habits changed: refresh widget and reminder alarms.
  Future<void> dataChanged() => _call('dataChanged');

  /// Foreground seconds per app between [start] and [end].
  Future<List<({String package, String label, int seconds})>> usage(
      DateTime start, DateTime end) async {
    try {
      final list = await _channel.invokeListMethod<Map<Object?, Object?>>('usage', {
            'start': start.millisecondsSinceEpoch,
            'end': end.millisecondsSinceEpoch,
          }) ??
          [];
      return [
        for (final m in list)
          (
            package: m['package'] as String,
            label: m['label'] as String,
            seconds: (m['seconds'] as num).toInt(),
          ),
      ];
    } on PlatformException {
      return [];
    }
  }

  Future<List<({String package, String label})>> launchableApps() async {
    try {
      final list = await _channel.invokeListMethod<Map<Object?, Object?>>('launchableApps') ?? [];
      return [
        for (final m in list) (package: m['package'] as String, label: m['label'] as String),
      ];
    } on PlatformException {
      return [];
    }
  }

  Future<List<String>> detectionLog() async {
    try {
      return await _channel.invokeListMethod<String>('detectionLog') ?? [];
    } on PlatformException {
      return [];
    }
  }

  /// Returns false if the accessibility service is not running.
  Future<bool> previewPause() async {
    try {
      return await _channel.invokeMethod<bool>('previewPause') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// "ok", "cancelled" or "error: ...".
  Future<String> exportBackup(String fileName) async {
    try {
      return await _channel.invokeMethod<String>('exportBackup', {'fileName': fileName}) ?? 'cancelled';
    } on PlatformException catch (e) {
      return 'error: ${e.message ?? e.code}';
    }
  }

  Future<String> importBackup() async =>
      await _channel.invokeMethod<String>('importBackup') ?? 'cancelled';

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException {
      // Native side unavailable; nothing useful to do.
    }
  }
}
