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
    const pages = [TodayScreen(), TasksScreen(), HabitsScreen(), StatsScreen()];
    // Back on any other tab returns to Today instead of leaving the app.
    return PopScope(
      canPop: tab.value == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) tab.value = 0;
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < pages.length; i++) _TabPage(active: i == tab.value, child: pages[i]),
          ],
        ),
        bottomNavigationBar: _NavBar(index: tab.value, onSelect: (i) => tab.value = i),
      ),
    );
  }
}

/// Text-only tab bar: the word is the button. Selected tab gets full ink and a short pista bar.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _labels = ['Today', 'Tasks', 'Habits', 'Stats'];

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.surfaceHigh)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < _labels.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    child: InkWell(
                      onTap: () => onSelect(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: ewText(
                              15,
                              i == index ? 720 : 520,
                              color: i == index ? c.text : c.muted,
                            ),
                            child: Text(_labels[i]),
                          ),
                          const SizedBox(height: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            width: i == index ? 18 : 0,
                            height: 3,
                            decoration: BoxDecoration(
                              color: c.good,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps every tab alive (like IndexedStack) but fades and lifts the active one in.
/// Inactive tabs don't paint, don't take touches, don't tick and are hidden from TalkBack.
class _TabPage extends StatelessWidget {
  const _TabPage({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: TickerMode(
          enabled: active,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: Duration(milliseconds: active ? 220 : 120),
            curve: Curves.easeOut,
            child: AnimatedSlide(
              offset: active ? Offset.zero : const Offset(0, 0.015),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
