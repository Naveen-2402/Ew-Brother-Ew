import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/games_repository.dart';
import '../../../domain/games.dart';
import '../../core/theme.dart';

/// One puzzle at a time: think, take a hint if needed, then reveal the answer.
/// "I got it" marks the puzzle solved (kept as a bit mask, one bit per puzzle).
class RiddlesScreen extends StatefulWidget {
  const RiddlesScreen({super.key});

  @override
  State<RiddlesScreen> createState() => _RiddlesScreenState();
}

class _RiddlesScreenState extends State<RiddlesScreen> {
  int _index = 0;
  bool _hint = false;
  bool _answer = false;
  int _mask = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    context.read<GamesRepository>().get(GamesRepository.riddlesSolved).then((m) {
      if (!mounted) return;
      setState(() {
        _mask = m;
        _loaded = true;
        // Start at the first puzzle not solved yet.
        final first = List.generate(riddles.length, (i) => i).where((i) => !_solved(i));
        _index = first.isEmpty ? 0 : first.first;
      });
    });
  }

  bool _solved(int i) => (_mask & (1 << i)) != 0;

  void _go(int delta) {
    setState(() {
      _index = (_index + delta) % riddles.length;
      if (_index < 0) _index += riddles.length;
      _hint = false;
      _answer = false;
    });
  }

  Future<void> _markSolved() async {
    HapticFeedback.selectionClick();
    final repo = context.read<GamesRepository>();
    setState(() => _mask |= 1 << _index);
    await repo.set(GamesRepository.riddlesSolved, _mask);
    if (mounted) _go(1);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final r = riddles[_index];
    final solved = _solved(_index);
    final count = List.generate(riddles.length, (i) => i).where(_solved).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Think different'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('$count / ${riddles.length}', style: ewText(15, 700, color: c.insta)),
            ),
          ),
        ],
      ),
      body: !_loaded
          ? const SizedBox.shrink()
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        Row(
                          children: [
                            Text('Puzzle ${_index + 1}', style: context.type.labelMedium),
                            if (solved) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.check_circle_rounded, size: 16, color: c.good),
                              const SizedBox(width: 4),
                              Text('solved', style: ewText(13, 600, color: c.good)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            r.question,
                            key: ValueKey(_index),
                            style: context.type.headlineSmall?.copyWith(height: 1.3),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _Reveal(
                          shown: _hint,
                          icon: Icons.lightbulb_outline_rounded,
                          color: c.warn,
                          label: 'Hint',
                          text: r.hint,
                          onShow: () => setState(() => _hint = true),
                        ),
                        const SizedBox(height: 10),
                        _Reveal(
                          shown: _answer,
                          icon: Icons.visibility_outlined,
                          color: c.good,
                          label: 'Show answer',
                          text: r.answer,
                          onShow: () => setState(() => _answer = true),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous',
                          onPressed: () => _go(-1),
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        const Spacer(),
                        if (_answer && !solved) ...[
                          FilledButton(onPressed: _markSolved, child: const Text('I got it')),
                          const SizedBox(width: 8),
                        ],
                        OutlinedButton(onPressed: () => _go(1), child: const Text('Next')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// A button that turns into the text it hides.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.shown,
    required this.icon,
    required this.color,
    required this.label,
    required this.text,
    required this.onShow,
  });

  final bool shown;
  final IconData icon;
  final Color color;
  final String label;
  final String text;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: shown
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: context.type.bodyLarge?.copyWith(color: c.text))),
                ],
              ),
            )
          : SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onShow,
                icon: Icon(icon, color: color, size: 20),
                label: Text(label),
              ),
            ),
    );
  }
}
