/// A "day" starts at [resetHour] (default 4 AM), not midnight.
///
/// MUST stay identical to android/.../data/LogicalDay.kt.
class LogicalDay {
  const LogicalDay._();

  static String keyFor(DateTime t, int resetHour) =>
      format(t.subtract(Duration(hours: resetHour)));

  static String format(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime parse(String key) {
    final p = key.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// When the day [key] starts, in local time.
  static DateTime startOf(String key, int resetHour) {
    final d = parse(key);
    return DateTime(d.year, d.month, d.day, resetHour);
  }

  static String minusDays(String key, int days) {
    final d = parse(key);
    return format(DateTime(d.year, d.month, d.day - days, 12));
  }

  /// Oldest first: [today-(n-1) ... today].
  static List<String> lastDays(String today, int n) =>
      [for (var i = n - 1; i >= 0; i--) minusDays(today, i)];
}
