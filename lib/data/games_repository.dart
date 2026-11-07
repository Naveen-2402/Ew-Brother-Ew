import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Best scores for the Play tab, kept in the settings table under "game_" keys.
///
/// Deliberately does NOT go through SettingsRepository: that one tells the counter service,
/// alarms and widget to reload, which a game score has nothing to do with. The native side
/// ignores keys it doesn't know, and backups include these rows automatically.
class GamesRepository {
  GamesRepository(this._db);

  final AppDatabase _db;

  static const sprintBest = 'game_sprint_best';
  static const seriesBest = 'game_series_best';
  static const riddlesSolved = 'game_riddles_solved';

  Future<int> get(String key) async {
    if (!_db.isOpen) return 0;
    try {
      final rows = await _db.db.query('settings', columns: ['value'], where: 'key = ?', whereArgs: [key]);
      if (rows.isEmpty) return 0;
      return int.tryParse(rows.first['value'] as String) ?? 0;
    } catch (_) {
      return 0; // a score is never worth an error on screen
    }
  }

  /// Saves [value] if it beats the stored one. Returns true for a new best.
  Future<bool> offerBest(String key, int value) async {
    final current = await get(key);
    if (value <= current) return false;
    await set(key, value);
    return true;
  }

  Future<void> set(String key, int value) async {
    if (!_db.isOpen) return;
    try {
      await _db.db.insert(
        'settings',
        {'key': key, 'value': '$value'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Database busy or closed for a restore: the score just isn't saved this time.
    }
  }
}
