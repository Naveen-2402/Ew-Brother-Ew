import 'package:sqflite/sqflite.dart';

import '../core/native_bridge.dart';

/// Opens focuspal.db through sqflite.
///
/// The schema is owned and migrated by the native EwDatabase helper (see EwDatabase.kt),
/// because the accessibility service can run before this UI is ever opened. So we:
///  1. ask native for the path (this runs native migrations), then
///  2. open the same file here WITHOUT a version (sqflite never creates or migrates).
class AppDatabase {
  AppDatabase(this._bridge);

  final NativeBridge _bridge;
  Database? _db;

  bool get isOpen => _db != null;

  Database get db {
    final d = _db;
    if (d == null) throw StateError('Database is closed');
    return d;
  }

  Future<void> open() async {
    if (_db != null) return;
    final path = await _bridge.dbPath();
    _db = await openDatabase(path, singleInstance: true);
  }

  /// Backup export/import replace or copy the file natively; close our handle first.
  Future<void> close() async {
    final d = _db;
    _db = null;
    await d?.close();
  }
}
