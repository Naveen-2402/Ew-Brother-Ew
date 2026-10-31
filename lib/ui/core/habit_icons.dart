import 'package:flutter/material.dart';

/// Habit icons stored by key in habits.icon. Const IconData keeps icon tree-shaking working.
const Map<String, IconData> habitIcons = {
  'spark': Icons.auto_awesome_rounded,
  'water': Icons.water_drop_rounded,
  'walk': Icons.directions_walk_rounded,
  'run': Icons.directions_run_rounded,
  'gym': Icons.fitness_center_rounded,
  'book': Icons.menu_book_rounded,
  'journal': Icons.edit_note_rounded,
  'meditate': Icons.self_improvement_rounded,
  'sleep': Icons.bedtime_rounded,
  'sun': Icons.wb_sunny_rounded,
  'food': Icons.restaurant_rounded,
  'code': Icons.code_rounded,
  'music': Icons.music_note_rounded,
  'money': Icons.savings_rounded,
  'call': Icons.call_rounded,
  'plant': Icons.local_florist_rounded,
};

IconData habitIcon(String key) => habitIcons[key] ?? Icons.auto_awesome_rounded;
