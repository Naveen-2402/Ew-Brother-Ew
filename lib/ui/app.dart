import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with SingleTickerProviderStateMixin {
  static const _pages = [TodayScreen(), TasksScreen(), HabitsScreen(), StatsScreen()];

  late final TabIndex _tab = context.read<TabIndex>();
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  late final Animation<double> _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, 0.018), end: Offset.zero)
      .animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));
  late int _shown = _tab.value;

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTab);
  }

  void _onTab() {
    if (_tab.value == _shown) return;
    // The old page disappears at once; only the new one animates in, so two pages never overlap.
    setState(() => _shown = _tab.value);
    _enter.forward(from: 0);
  }

  @override
  void dispose() {
    _tab.removeListener(_onTab);
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Back on any other tab returns to Today instead of leaving the app.
    return PopScope(
      canPop: _shown == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _tab.value = 0;
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < _pages.length; i++)
              _TabPage(
                key: ValueKey(i),
                active: i == _shown,
                fade: _fade,
                slide: _slide,
                child: _pages[i],
              ),
          ],
        ),
        bottomNavigationBar: _NavBar(
          index: _shown,
          onSelect: (i) {
            if (i == _tab.value) return;
            HapticFeedback.selectionClick();
            _tab.value = i;
          },
        ),
      ),
    );
  }
}

/// Floating bar. A soft pill slides behind the selected tab, which gets the accent colour
/// and a filled icon; the others stay quiet (outlined icon, muted label).
class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (label: 'Today', icon: Icons.wb_sunny_outlined, active: Icons.wb_sunny_rounded),
    (label: 'Tasks', icon: Icons.check_circle_outline_rounded, active: Icons.check_circle_rounded),
    (label: 'Habits', icon: Icons.local_florist_outlined, active: Icons.local_florist_rounded),
    (label: 'Stats', icon: Icons.insights_outlined, active: Icons.insights_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const n = 4;
    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          child: Container(
            height: 66,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: c.surfaceHigh),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                // The pill behind the selected tab.
                AnimatedAlign(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  alignment: Alignment(-1 + 2 * index / (n - 1), 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.good.withValues(alpha: dark ? 0.16 : 0.13),
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: _NavItem(
                          label: _items[i].label,
                          icon: i == index ? _items[i].active : _items[i].icon,
                          selected: i == index,
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: Colors.transparent,
        highlightColor: c.surfaceHigh.withValues(alpha: 0.5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(icon, key: ValueKey(icon), size: 22, color: selected ? c.good : c.muted),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: ewText(11.5, selected ? 700 : 520, color: selected ? c.text : c.muted),
              child: Text(label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps every tab alive (like IndexedStack). Inactive tabs are Offstage: not painted,
/// no touches, no tickers, hidden from TalkBack. The active one fades and lifts in.
/// The tree has the same shape whether a tab is active or not, so no tab loses its state.
class _TabPage extends StatelessWidget {
  const _TabPage({
    super.key,
    required this.active,
    required this.fade,
    required this.slide,
    required this.child,
  });

  final bool active;
  final Animation<double> fade;
  final Animation<Offset> slide;
  final Widget child;

  static const _still = AlwaysStoppedAnimation<double>(1);
  static const _rest = AlwaysStoppedAnimation<Offset>(Offset.zero);

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !active,
      child: TickerMode(
        enabled: active,
        child: FadeTransition(
          opacity: active ? fade : _still,
          child: SlideTransition(
            position: active ? slide : _rest,
            child: child,
          ),
        ),
      ),
    );
  }
}
