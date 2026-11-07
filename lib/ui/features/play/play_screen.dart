import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/games_repository.dart';
import '../../../domain/games.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'math_sprint_screen.dart';
import 'riddles_screen.dart';
import 'series_screen.dart';

/// The Play tab: short brain games to reach for instead of another reel.
class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  int _sprint = 0;
  int _series = 0;
  int _solved = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<GamesRepository>();
    final sprint = await repo.get(GamesRepository.sprintBest);
    final series = await repo.get(GamesRepository.seriesBest);
    final mask = await repo.get(GamesRepository.riddlesSolved);
    if (!mounted) return;
    setState(() {
      _sprint = sprint;
      _series = series;
      _solved = solvedCount(mask);
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (!mounted) return;
    _load(); // new best scores
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text('Play', style: context.type.headlineMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Two minutes for your brain instead of twenty for the feed.',
              style: context.type.bodyMedium?.copyWith(color: c.muted),
            ),
          ),
          FadeSlideIn(
            index: 0,
            child: _GameCard(
              icon: Icons.bolt_rounded,
              color: c.warn,
              title: 'Math Sprint',
              body: '60 seconds of mental maths. Gets harder as you go.',
              stat: _sprint == 0 ? 'No best yet' : 'Best $_sprint',
              onTap: () => _open(const MathSprintScreen()),
            ),
          ),
          FadeSlideIn(
            index: 1,
            child: _GameCard(
              icon: Icons.timeline_rounded,
              color: c.shorts,
              title: 'What comes next',
              body: 'Spot the pattern in 10 number series.',
              stat: _series == 0 ? 'No best yet' : 'Best $_series / ${SeriesScreen.rounds}',
              onTap: () => _open(const SeriesScreen()),
            ),
          ),
          FadeSlideIn(
            index: 2,
            child: _GameCard(
              icon: Icons.psychology_alt_rounded,
              color: c.insta,
              title: 'Think different',
              body: 'Lateral-thinking and logic puzzles, with a hint when you\'re stuck.',
              stat: '$_solved of ${riddles.length} solved',
              onTap: () => _open(const RiddlesScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// How many riddles are marked solved in the stored bit mask.
int solvedCount(int mask) {
  var n = 0;
  for (var i = 0; i < riddles.length; i++) {
    if ((mask & (1 << i)) != 0) n++;
  }
  return n;
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.stat,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.type.titleMedium),
                      const SizedBox(height: 2),
                      Text(body, style: context.type.bodySmall),
                      const SizedBox(height: 8),
                      Text(stat, style: ewText(13, 700, color: color)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
