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

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdayLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const monthLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
