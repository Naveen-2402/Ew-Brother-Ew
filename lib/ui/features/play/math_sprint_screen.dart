import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/games_repository.dart';
import '../../../domain/games.dart';
import '../../core/theme.dart';

/// 60 seconds of mental arithmetic. Type the answer on the keypad; a right answer moves on by
/// itself, a wrong one (once it has as many digits as the answer) clears with a shake.
class MathSprintScreen extends StatefulWidget {
  const MathSprintScreen({super.key});

  static const seconds = 60;

  @override
  State<MathSprintScreen> createState() => _MathSprintScreenState();
}

enum _Phase { ready, playing, done }

class _MathSprintScreenState extends State<MathSprintScreen> {
  final _gen = SprintGenerator();
  final _clock = Stopwatch();
  Timer? _ticker;

  _Phase _phase = _Phase.ready;
  late SprintQuestion _q = _gen.next(0);
  String _typed = '';
  int _score = 0;
  int _wrong = 0;
  bool _flashWrong = false;
  bool _newBest = false;
  int _best = 0;

  int get _left => (MathSprintScreen.seconds - _clock.elapsed.inMilliseconds / 1000).ceil().clamp(0, MathSprintScreen.seconds);

  @override
  void initState() {
    super.initState();
    context.read<GamesRepository>().get(GamesRepository.sprintBest).then((b) {
      if (mounted) setState(() => _best = b);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() {
      _phase = _Phase.playing;
      _score = 0;
      _wrong = 0;
      _typed = '';
      _newBest = false;
      _q = _gen.next(0);
    });
    _clock
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      if (_left <= 0) {
        _finish();
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    _clock.stop();
    final repo = context.read<GamesRepository>();
    setState(() => _phase = _Phase.done);
    HapticFeedback.mediumImpact();
    final isBest = await repo.offerBest(GamesRepository.sprintBest, _score);
    if (!mounted) return;
    setState(() {
      _newBest = isBest;
      if (isBest) _best = _score;
    });
  }

  void _key(String k) {
    if (_phase != _Phase.playing) return;
    if (k == '⌫') {
      if (_typed.isNotEmpty) setState(() => _typed = _typed.substring(0, _typed.length - 1));
      return;
    }
    if (k == 'skip') {
      setState(() {
        _typed = '';
        _q = _gen.next(_score);
      });
      return;
    }
    if (_typed.length >= 5) return;
    final typed = _typed + k;
    final answer = '${_q.answer}';
    if (typed == answer) {
      HapticFeedback.selectionClick();
      setState(() {
        _score++;
        _typed = '';
        _q = _gen.next(_score);
      });
    } else if (typed.length >= answer.length) {
      HapticFeedback.heavyImpact();
      setState(() {
        _wrong++;
        _typed = '';
        _flashWrong = true;
      });
      Future.delayed(const Duration(milliseconds: 260), () {
        if (mounted) setState(() => _flashWrong = false);
      });
    } else {
      setState(() => _typed = typed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Scaffold(
      appBar: AppBar(title: const Text('Math Sprint')),
      body: SafeArea(
        top: false,
        child: switch (_phase) {
          _Phase.ready => _Intro(best: _best, onStart: _start),
          _Phase.done => _Result(
              score: _score,
              wrong: _wrong,
              best: _best,
              newBest: _newBest,
              onAgain: _start,
              onDone: () => Navigator.of(context).pop(),
            ),
          _Phase.playing => Column(
              children: [
                // Time bar.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      Text('$_left s', style: ewText(16, 700, color: _left <= 10 ? c.bad : c.text)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _left / MathSprintScreen.seconds,
                            minHeight: 6,
                            backgroundColor: c.surfaceHigh,
                            color: _left <= 10 ? c.bad : c.warn,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('$_score', style: ewText(20, 780, width: 82, color: c.good)),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_q.text, style: ewText(44, 760, width: 82, color: c.text)),
                        const SizedBox(height: 16),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          constraints: const BoxConstraints(minWidth: 140),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: _flashWrong ? c.bad.withValues(alpha: 0.18) : c.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _flashWrong ? c.bad : c.surfaceHigh, width: 1.5),
                          ),
                          child: Text(
                            _typed.isEmpty ? '?' : _typed,
                            textAlign: TextAlign.center,
                            style: ewText(34, 760, width: 82, color: _typed.isEmpty ? c.muted : c.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _Keypad(onKey: _key),
              ],
            ),
        },
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});

  final ValueChanged<String> onKey;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['skip', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          for (final row in _rows)
            Row(
              children: [
                for (final k in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Material(
                        color: k.length == 1 ? c.surface : c.surfaceHigh,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => onKey(k),
                          child: SizedBox(
                            height: 58,
                            child: Center(
                              child: switch (k) {
                                '⌫' => Icon(Icons.backspace_outlined, color: c.text),
                                'skip' => Text('Skip', style: context.type.labelLarge?.copyWith(color: c.muted)),
                                _ => Text(k, style: ewText(24, 700, color: c.text)),
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.best, required this.onStart});

  final int best;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Icon(Icons.bolt_rounded, size: 64, color: c.warn),
          const SizedBox(height: 16),
          Text('${MathSprintScreen.seconds} seconds', textAlign: TextAlign.center, style: context.type.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Type each answer on the keypad. Right answers move on by themselves. '
            'It starts with + and −, then adds × and ÷.',
            textAlign: TextAlign.center,
            style: context.type.bodyMedium?.copyWith(color: c.muted),
          ),
          const SizedBox(height: 16),
          if (best > 0) Text('Your best: $best', textAlign: TextAlign.center, style: ewText(16, 700, color: c.warn)),
          const Spacer(),
          FilledButton(onPressed: onStart, child: const Text('Start')),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.score,
    required this.wrong,
    required this.best,
    required this.newBest,
    required this.onAgain,
    required this.onDone,
  });

  final int score;
  final int wrong;
  final int best;
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
          Text('$score', textAlign: TextAlign.center, style: ewText(88, 800, width: 75, color: c.good, height: 1)),
          Text('correct in ${MathSprintScreen.seconds} s', textAlign: TextAlign.center, style: context.type.titleMedium),
          const SizedBox(height: 8),
          Text(
            '$wrong wrong · best $best',
            textAlign: TextAlign.center,
            style: context.type.bodyMedium?.copyWith(color: c.muted),
          ),
          const Spacer(),
          FilledButton(onPressed: onAgain, child: const Text('Play again')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }
}
