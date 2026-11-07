import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/games_repository.dart';
import '../../../domain/games.dart';
import '../../core/theme.dart';

/// Ten number series per game, getting harder. Pick what comes next; the rule is shown after.
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key});

  static const rounds = 10;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  final _gen = SeriesGenerator();

  int _round = 0;
  int _score = 0;
  late SeriesPuzzle _p = _gen.next(0);
  int? _picked;
  bool _done = false;
  bool _newBest = false;

  void _pick(int option) {
    if (_picked != null) return;
    final right = option == _p.answer;
    if (right) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() {
      _picked = option;
      if (right) _score++;
    });
  }

  Future<void> _next() async {
    if (_round + 1 >= SeriesScreen.rounds) {
      final repo = context.read<GamesRepository>();
      setState(() => _done = true);
      final best = await repo.offerBest(GamesRepository.seriesBest, _score);
      if (mounted) setState(() => _newBest = best);
      return;
    }
    setState(() {
      _round++;
      _picked = null;
      _p = _gen.next(_round);
    });
  }

  void _restart() {
    setState(() {
      _round = 0;
      _score = 0;
      _picked = null;
      _done = false;
      _newBest = false;
      _p = _gen.next(0);
    });
  }

  Widget _option(int o) => _OptionButton(
        label: '$o',
        state: _picked == null
            ? _OptionState.idle
            : (o == _p.answer ? _OptionState.right : (o == _picked ? _OptionState.wrong : _OptionState.faded)),
        onTap: () => _pick(o),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Scaffold(
      appBar: AppBar(title: const Text('What comes next')),
      body: SafeArea(
        top: false,
        child: _done
            ? _Done(score: _score, newBest: _newBest, onAgain: _restart, onDone: () => Navigator.of(context).pop())
            // Scrolls on short or landscape screens instead of overflowing.
            : LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: IntrinsicHeight(child: _game(context, c)),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _game(BuildContext context, EwColors c) {
    return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('${_round + 1} of ${SeriesScreen.rounds}', style: context.type.labelMedium),
                        const Spacer(),
                        Text('$_score right', style: ewText(14, 700, color: c.good)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_round + (_picked == null ? 0 : 1)) / SeriesScreen.rounds,
                        minHeight: 6,
                        backgroundColor: c.surfaceHigh,
                        color: c.shorts,
                      ),
                    ),
                    const Spacer(),
                    // The series, then the blank to fill.
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final n in _p.shown) _Number('$n', color: c.text, fill: c.surface),
                        _Number(
                          _picked == null ? '?' : '${_p.answer}',
                          color: _picked == null ? c.shorts : c.good,
                          fill: (_picked == null ? c.shorts : c.good).withValues(alpha: 0.14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    AnimatedOpacity(
                      opacity: _picked == null ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _picked == null ? ' ' : (_picked == _p.answer ? 'Right. ${_p.rule}' : 'Not quite. ${_p.rule}'),
                        textAlign: TextAlign.center,
                        style: context.type.bodyLarge?.copyWith(color: _picked == _p.answer ? c.good : c.warn),
                      ),
                    ),
                    const Spacer(),
                    // Two rows of two choices.
                    for (var row = 0; row < 2; row++)
                      Padding(
                        padding: EdgeInsets.only(top: row == 0 ? 0 : 10),
                        child: Row(
                          children: [
                            for (var col = 0; col < 2; col++) ...[
                              if (col == 1) const SizedBox(width: 10),
                              Expanded(child: SizedBox(height: 56, child: _option(_p.options[row * 2 + col]))),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _picked == null ? null : _next,
                      child: Text(_round + 1 >= SeriesScreen.rounds ? 'See score' : 'Next'),
                    ),
                  ],
                ),
              );
  }
}

class _Number extends StatelessWidget {
  const _Number(this.text, {required this.color, required this.fill});

  final String text;
  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(14)),
      child: Text(text, textAlign: TextAlign.center, style: ewText(24, 760, width: 82, color: color)),
    );
  }
}

enum _OptionState { idle, right, wrong, faded }

class _OptionButton extends StatelessWidget {
  const _OptionButton({required this.label, required this.state, required this.onTap});

  final String label;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final (bg, fg, border) = switch (state) {
      _OptionState.idle => (c.surface, c.text, c.surfaceHigh),
      _OptionState.right => (c.good.withValues(alpha: 0.18), c.good, c.good),
      _OptionState.wrong => (c.bad.withValues(alpha: 0.16), c.bad, c.bad),
      _OptionState.faded => (c.surface, c.muted, c.surfaceHigh),
    };
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: state == _OptionState.idle ? onTap : null,
        child: Center(child: Text(label, style: ewText(22, 740, width: 82, color: fg))),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.score, required this.newBest, required this.onAgain, required this.onDone});

  final int score;
  final bool newBest;
  final VoidCallback onAgain;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          if (newBest) ...[
            Icon(Icons.emoji_events_rounded, size: 56, color: c.warn),
            const SizedBox(height: 8),
            Text('New best!', textAlign: TextAlign.center, style: ewText(18, 760, color: c.warn)),
          ],
          Text(
            '$score / ${SeriesScreen.rounds}',
            textAlign: TextAlign.center,
            style: ewText(72, 800, width: 75, color: c.good, height: 1),
          ),
          const SizedBox(height: 8),
          Text('patterns spotted', textAlign: TextAlign.center, style: context.type.titleMedium),
          const Spacer(),
          FilledButton(onPressed: onAgain, child: const Text('Play again')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }
}
