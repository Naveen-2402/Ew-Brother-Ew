import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/logical_day.dart';
import '../core/native_bridge.dart';
import '../data/app_database.dart';
import '../data/repositories.dart';
import '../data/settings_keys.dart';
import '../domain/models.dart';

/// App-wide state: settings snapshot, permission state and the current logical day.
/// Screen view models listen to this plus [DataSignal].
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({
    required this.bridge,
    required this.database,
    required this.settingsRepo,
    required this.signal,
  });

  final NativeBridge bridge;
  final AppDatabase database;
  final SettingsRepository settingsRepo;
  final DataSignal signal;

  AppSettings settings = const AppSettings({});
  PermissionState permissions = const PermissionState.unknown();
  String today = '';

  StreamSubscription<String>? _sub;
  Timer? _reelDebounce;
  Timer? _dayTimer;

  DateTime get dayStart => LogicalDay.startOf(today, settings.dayResetHour);

  Future<void> init() async {
    settings = await settingsRepo.load();
    await _applyPendingResetHour();
    today = LogicalDay.keyFor(DateTime.now(), settings.dayResetHour);
    permissions = await bridge.permissions();
    WidgetsBinding.instance.addObserver(this);
    _sub = bridge.events.listen(_onNative);
    _scheduleDayRollover();
  }

  /// Fires at the next reset hour so an app left open overnight moves to the new day.
  void _scheduleDayRollover() {
    _dayTimer?.cancel();
    final s = LogicalDay.startOf(today, settings.dayResetHour);
    // Calendar day + 1 (not +24 h), so clock changes don't make it fire early.
    final next = DateTime(s.year, s.month, s.day + 1, settings.dayResetHour);
    final wait = next.difference(DateTime.now()) + const Duration(seconds: 2);
    _dayTimer = Timer(wait.isNegative ? const Duration(seconds: 2) : wait, () async {
      if (database.isOpen) await _applyPendingResetHour();
      _checkDay();
      if (database.isOpen) signal.bump();
      _scheduleDayRollover();
    });
  }

  void _onNative(String event) {
    switch (event) {
      case 'reelCounted':
        // A fast swipe sends several events; reload once after it settles
        // (also gives the native DB write time to land).
        _reelDebounce?.cancel();
        _reelDebounce = Timer(const Duration(milliseconds: 400), () {
          if (database.isOpen) signal.bump();
        });
      case 'dataChanged':
        if (database.isOpen) signal.bump();
      case 'settingsChanged':
        if (database.isOpen) reloadSettings();
      case 'serviceChanged':
        refreshPermissions();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Skipped while a backup restore has the database closed; it reloads itself after.
    if (state == AppLifecycleState.resumed && database.isOpen) {
      _onResume();
    }
  }

  Future<void> _onResume() async {
    await refreshPermissions();
    await _applyPendingResetHour();
    _checkDay();
    signal.bump();
  }

  /// Same rule as Store.applyPendingResetHour in Kotlin: a new "day starts at" hour only
  /// applies once the current day (under the old hour) is over, so it can't reset today's count.
  Future<void> _applyPendingResetHour() async {
    final next = settings.pendingResetHour;
    if (next == null) return;
    final current = LogicalDay.keyFor(DateTime.now(), settings.dayResetHour);
    if (current.compareTo(settings.pendingResetAfter) <= 0) return;
    await update({
      SettingsKeys.dayResetHour: '$next',
      SettingsKeys.dayResetNext: '',
      SettingsKeys.dayResetNextAfter: '',
    });
  }

  /// Settings > "New day starts at". Takes effect when the current day ends.
  Future<void> setResetHour(int hour) async {
    if (hour == settings.dayResetHour) {
      if (settings.pendingResetHour != null) {
        await update({SettingsKeys.dayResetNext: '', SettingsKeys.dayResetNextAfter: ''});
      }
      return;
    }
    await update({SettingsKeys.dayResetNext: '$hour', SettingsKeys.dayResetNextAfter: today});
  }

  void _checkDay() {
    final now = LogicalDay.keyFor(DateTime.now(), settings.dayResetHour);
    if (now != today) {
      today = now;
      _scheduleDayRollover();
      notifyListeners();
    }
  }

  Future<void> refreshPermissions() async {
    permissions = await bridge.permissions();
    notifyListeners();
  }

  Future<void> reloadSettings() async {
    try {
      settings = await settingsRepo.load();
    } catch (_) {
      return; // database closed (restore in progress); reopenAfterImport reloads
    }
    _checkDay();
    notifyListeners();
  }

  /// Write settings, update the snapshot immediately, notify native.
  /// If the write fails the snapshot is rolled back, so the screen never shows an unsaved value.
  Future<bool> update(Map<String, String> values) async {
    final before = settings;
    settings = settings.merge(values);
    _checkDay();
    notifyListeners();
    try {
      await settingsRepo.set(values);
    } catch (_) {
      settings = before;
      _checkDay();
      notifyListeners();
      return false;
    }
    if (values.containsKey(SettingsKeys.dayResetHour)) signal.bump();
    return true;
  }

  Future<void> setFlag(String key, bool on) async {
    await update({key: on ? '1' : '0'});
  }

  /// Re-read everything after a backup import replaced the database file.
  Future<void> reopenAfterImport() async {
    await database.open();
    await reloadSettings();
    signal.bump();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _reelDebounce?.cancel();
    _dayTimer?.cancel();
    super.dispose();
  }
}
