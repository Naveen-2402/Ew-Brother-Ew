import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_controller.dart';
import 'core/theme.dart';
import 'features/habits/habits_screen.dart';
import 'features/habits/habits_view_model.dart';
import 'features/stats/stats_screen.dart';
import 'features/stats/stats_view_model.dart';
import 'features/tasks/tasks_screen.dart';
import 'features/tasks/tasks_view_model.dart';
import 'features/today/today_screen.dart';
import 'features/today/today_view_model.dart';

class EwApp extends StatelessWidget {
  const EwApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.select<AppController, String>((a) => a.settings.theme);
    return MaterialApp(
      title: 'Ew Brother Ew',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (theme) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      themeAnimationDuration: const Duration(milliseconds: 200),
      home: const HomeShell(),
    );
  }
}

/// Which bottom tab is open; lets Today jump to Tasks/Habits.
class TabIndex extends ValueNotifier<int> {
  TabIndex() : super(0);
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TabIndex()),
        ChangeNotifierProvider(create: (c) => TodayViewModel.of(c)),
        ChangeNotifierProvider(create: (c) => TasksViewModel.of(c)),
        ChangeNotifierProvider(create: (c) => HabitsViewModel.of(c)),
        ChangeNotifierProvider(create: (c) => StatsViewModel.of(c)),
      ],
      child: const _Shell(),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell();

  @override
  Widget build(BuildContext context) {
    final tab = context.watch<TabIndex>();
    return Scaffold(
      body: IndexedStack(
        index: tab.value,
        children: const [TodayScreen(), TasksScreen(), HabitsScreen(), StatsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.value,
        onDestinationSelected: (i) => tab.value = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today_rounded), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.check_circle_outline_rounded), selectedIcon: Icon(Icons.check_circle_rounded), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.local_fire_department_outlined), selectedIcon: Icon(Icons.local_fire_department_rounded), label: 'Habits'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Stats'),
        ],
      ),
    );
  }
}
