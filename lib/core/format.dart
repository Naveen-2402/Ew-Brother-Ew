/// Short human durations: "42 min", "3 h 12 min", "0 min".
String formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// "4 AM", "noon", "midnight", "9 PM".
String formatHour(int h) {
  if (h == 0) return 'midnight';
  if (h == 12) return 'noon';
  return h < 12 ? '$h AM' : '${h - 12} PM';
}

/// "HH:mm" -> "8:00 AM".
String formatClock(String hhmm) {
  final p = hhmm.split(':');
  final h = int.tryParse(p.first) ?? 0;
  final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

String twoDigits(int v) => v.toString().padLeft(2, '0');

/// Task reminder: "Daily 6:30 PM", "Today 6:30 PM", "Tomorrow 9:00 AM", "12 Nov, 9:00 AM".
String formatReminder(DateTime at, {required bool daily, DateTime? now}) {
  final clock = formatClock('${at.hour}:${twoDigits(at.minute)}');
  if (daily) return 'Daily $clock';
  final n = now ?? DateTime.now();
  // UTC dates: a 23-hour daylight-saving day would otherwise count as 0 days.
  final days = DateTime.utc(at.year, at.month, at.day).difference(DateTime.utc(n.year, n.month, n.day)).inDays;
  if (days == 0) return 'Today $clock';
  if (days == 1) return 'Tomorrow $clock';
  final date = '${at.day} ${monthShort[at.month - 1]}${at.year == n.year ? '' : ' ${at.year}'}';
  return '$date, $clock';
}

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdayLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const monthLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today", "Yesterday", "Tue 21 Oct" (year added when not this year).
String formatDayKey(String key, String today) {
  final d = DateTime.parse(key);
  final t = DateTime.parse(today);
  final diff = DateTime(t.year, t.month, t.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final base = '${weekdayShort[d.weekday - 1]} ${d.day} ${monthShort[d.month - 1]}';
  return d.year == t.year ? base : '$base ${d.year}';
}

/// "21 Oct" or "21 Oct 2025".
String formatShortDate(String key, {bool withYear = false}) {
  final d = DateTime.parse(key);
  return withYear ? '${d.day} ${monthShort[d.month - 1]} ${d.year}' : '${d.day} ${monthShort[d.month - 1]}';
}
