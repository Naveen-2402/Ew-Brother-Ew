import 'dart:math';

import 'package:ew_brother_ew/domain/games.dart';
import 'package:ew_brother_ew/ui/features/play/play_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Works out "12 × 7" style questions independently of the generator.
int evaluate(String text) {
  final p = text.split(' ');
  final a = int.parse(p[0]);
  final b = int.parse(p[2]);
  return switch (p[1]) {
    '+' => a + b,
    '−' => a - b,
    '×' => a * b,
    '÷' => a ~/ b,
    _ => throw ArgumentError(text),
  };
}

void main() {
  group('math sprint', () {
    test('answers are right, whole and typeable at every level', () {
      for (var seed = 0; seed < 50; seed++) {
        final g = SprintGenerator(Random(seed));
        for (var level = 0; level < 40; level++) {
          final q = g.next(level);
          expect(q.answer, evaluate(q.text), reason: q.text);
          expect(q.answer, inInclusiveRange(0, 9999), reason: q.text);
          if (q.text.contains('÷')) {
            final p = q.text.split(' ');
            expect(int.parse(p[0]) % int.parse(p[2]), 0, reason: 'divides exactly: ${q.text}');
          }
        }
      }
    });

    test('early levels only add and subtract', () {
      final g = SprintGenerator(Random(1));
      for (var i = 0; i < 200; i++) {
        final q = g.next(0);
        expect(q.text.contains('×') || q.text.contains('÷'), isFalse, reason: q.text);
      }
    });
  });

  group('what comes next', () {
    test('four different positive options, one of them the answer', () {
      for (var seed = 0; seed < 50; seed++) {
        final g = SeriesGenerator(Random(seed));
        for (var level = 0; level < 12; level++) {
          final p = g.next(level);
          expect(p.shown.length, 5);
          expect(p.options.length, 4);
          expect(p.options.toSet().length, 4, reason: '${p.options}');
          expect(p.options, contains(p.answer));
          expect(p.options.every((o) => o > 0), isTrue, reason: '${p.options}');
          expect(p.shown.every((n) => n > 0), isTrue, reason: '${p.shown}');
          expect(p.rule, isNotEmpty);
        }
      }
    });
  });

  group('think different', () {
    test('puzzles are complete and fit the solved bit mask', () {
      expect(riddles, isNotEmpty);
      expect(riddles.length, lessThanOrEqualTo(60)); // one bit each in a 64-bit int
      for (final r in riddles) {
        expect(r.question.trim(), isNotEmpty);
        expect(r.hint.trim(), isNotEmpty);
        expect(r.answer.trim(), isNotEmpty);
      }
    });

    test('solved count reads the bit mask', () {
      expect(solvedCount(0), 0);
      expect(solvedCount(1), 1);
      expect(solvedCount(1 | 4 | 8), 3);
      expect(solvedCount((1 << riddles.length) - 1), riddles.length);
    });
  });
}
