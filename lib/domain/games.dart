import 'dart:math';

/// Pure logic for the Play tab. No Flutter imports, so it's unit-tested in test/games_test.dart.

// ============================================================================ math sprint

class SprintQuestion {
  const SprintQuestion(this.text, this.answer);

  /// e.g. "12 × 7"
  final String text;
  final int answer;
}

/// Mental-arithmetic questions that get harder as [level] rises (level = correct answers so far).
/// Every answer is a whole number from 0 to 9999, so it can be typed on the keypad.
class SprintGenerator {
  SprintGenerator([Random? random]) : _r = random ?? Random();

  final Random _r;

  int _between(int lo, int hi) => lo + _r.nextInt(hi - lo + 1);

  SprintQuestion next(int level) {
    // Levels 0-4: + and - with small numbers; 5-9: add ×; 10+: add ÷ and bigger numbers.
    final ops = level < 5 ? ['+', '-'] : (level < 10 ? ['+', '-', '×'] : ['+', '-', '×', '÷']);
    final op = ops[_r.nextInt(ops.length)];
    final big = level >= 10;
    switch (op) {
      case '+':
        final a = big ? _between(20, 99) : _between(2, 20 + level * 4);
        final b = big ? _between(20, 99) : _between(2, 20 + level * 4);
        return SprintQuestion('$a + $b', a + b);
      case '-':
        final a = big ? _between(40, 150) : _between(5, 25 + level * 4);
        final b = _between(1, a); // never negative
        return SprintQuestion('$a − $b', a - b);
      case '×':
        final a = _between(2, big ? 15 : 9);
        final b = _between(2, big ? 15 : 12);
        return SprintQuestion('$a × $b', a * b);
      default: // ÷ : built from a product, so it always divides exactly
        final b = _between(2, 12);
        final q = _between(2, 12);
        return SprintQuestion('${b * q} ÷ $b', q);
    }
  }
}

// ============================================================================ what comes next

class SeriesPuzzle {
  const SeriesPuzzle({required this.shown, required this.answer, required this.options, required this.rule});

  /// The numbers shown, oldest first.
  final List<int> shown;
  final int answer;

  /// Four different choices, one of them [answer].
  final List<int> options;

  /// Plain explanation shown after answering.
  final String rule;
}

/// Number patterns. Difficulty picks from more pattern kinds as [level] rises.
class SeriesGenerator {
  SeriesGenerator([Random? random]) : _r = random ?? Random();

  final Random _r;

  int _between(int lo, int hi) => lo + _r.nextInt(hi - lo + 1);

  SeriesPuzzle next(int level) {
    final kinds = level < 3 ? 2 : (level < 6 ? 4 : 6);
    final kind = _r.nextInt(kinds);
    final List<int> seq; // 6 numbers: 5 shown + the answer
    final String rule;
    switch (kind) {
      case 0: // add the same amount
        final a = _between(1, 20);
        final d = _between(2, 12);
        seq = [for (var i = 0; i < 6; i++) a + d * i];
        rule = 'Add $d each time.';
      case 1: // subtract the same amount
        final d = _between(2, 9);
        final a = d * 6 + _between(1, 30);
        seq = [for (var i = 0; i < 6; i++) a - d * i];
        rule = 'Take away $d each time.';
      case 2: // multiply
        final a = _between(1, 4);
        final m = _between(2, 3);
        seq = [for (var i = 0; i < 6; i++) a * pow(m, i).toInt()];
        rule = 'Multiply by $m each time.';
      case 3: // the gap grows by one
        final a = _between(1, 10);
        final g = _between(1, 4);
        seq = [a];
        for (var i = 0; i < 5; i++) {
          seq.add(seq.last + g + i);
        }
        rule = 'The gap grows by 1: +$g, +${g + 1}, +${g + 2}…';
      case 4: // squares
        final s = _between(1, 6);
        seq = [for (var i = 0; i < 6; i++) (s + i) * (s + i)];
        rule = 'Square numbers: $s², ${s + 1}², ${s + 2}²…';
      default: // each number is the sum of the two before
        final a = _between(1, 5);
        final b = _between(a, a + 5);
        seq = [a, b];
        while (seq.length < 6) {
          seq.add(seq[seq.length - 1] + seq[seq.length - 2]);
        }
        rule = 'Each number is the sum of the two before it.';
    }
    final answer = seq.last;
    return SeriesPuzzle(
      shown: seq.sublist(0, 5),
      answer: answer,
      options: _options(answer, seq[4]),
      rule: rule,
    );
  }

  /// The answer plus three near misses, positive and all different, shuffled.
  List<int> _options(int answer, int previous) {
    final set = <int>{answer};
    final gap = (answer - previous).abs().clamp(1, 1000);
    final candidates = [
      answer + 1, answer - 1, answer + 2, answer - 2,
      answer + gap, answer - gap, previous + 1, answer + 10, answer * 2,
    ]..shuffle(_r);
    for (final c in candidates) {
      if (set.length == 4) break;
      if (c > 0) set.add(c);
    }
    var extra = answer + 3;
    while (set.length < 4) {
      set.add(extra++);
    }
    return set.toList()..shuffle(_r);
  }
}

// ============================================================================ think different

class Riddle {
  const Riddle(this.question, this.hint, this.answer);

  final String question;
  final String hint;
  final String answer;
}

/// Lateral-thinking and logic puzzles. Each answer is checked by hand (see the test file).
const riddles = <Riddle>[
  Riddle(
    'Two coins add up to ₹30. One of them is not a ₹10 coin. What are the two coins?',
    'Read "one of them" very carefully.',
    'A ₹20 coin and a ₹10 coin. The ₹20 one is the coin that is not ₹10.',
  ),
  Riddle(
    'A clock shows 3:15. What is the angle between the hour and minute hands?',
    'The hour hand doesn\'t stay on the 3.',
    '7.5°. The minute hand is on the 3, and the hour hand has moved a quarter of the way to the 4 (a quarter of 30°).',
  ),
  Riddle(
    'A patch of water lilies doubles in size every day. It covers the whole lake on day 30. On which day did it cover half the lake?',
    'Think backwards from day 30.',
    'Day 29. It doubles once more to cover the whole lake on day 30.',
  ),
  Riddle(
    'A drawer has 10 black socks and 10 white socks. In the dark, how many socks must you take to be sure of a matching pair?',
    'There are only two colours.',
    '3. With two colours, any three socks must include two of the same colour.',
  ),
  Riddle(
    'In a race, you overtake the runner in second place. What place are you in now?',
    'Whose place did you take?',
    'Second. You took their place; the leader is still ahead of you.',
  ),
  Riddle(
    'A pen and a notebook cost ₹110 together. The notebook costs ₹100 more than the pen. How much is the pen?',
    'The quick answer, ₹10, is wrong. Check it.',
    '₹5. Then the notebook is ₹105, and 5 + 105 = 110.',
  ),
  Riddle(
    'If 5 machines make 5 bottles in 5 minutes, how long do 100 machines take to make 100 bottles?',
    'How long does one machine take for one bottle?',
    '5 minutes. Each machine makes one bottle in 5 minutes, all working at the same time.',
  ),
  Riddle(
    'Six friends meet and each shakes hands once with every other friend. How many handshakes is that?',
    'Each handshake involves two people.',
    '15. Each of the 6 shakes 5 hands: 6 × 5 = 30, and every handshake was counted twice.',
  ),
  Riddle(
    'Some months have 31 days and some have 30. How many months have 28 days?',
    'It doesn\'t say "only 28".',
    'All 12. Every month has at least 28 days.',
  ),
  Riddle(
    'What is the largest number of pieces you can cut a round cake into with 3 straight cuts? Pieces can\'t be moved between cuts.',
    'Not every cut has to be from the top.',
    '8. Two cuts from the top crossing in the middle make 4, then one cut through the side, parallel to the plate, doubles them.',
  ),
  Riddle(
    'Three switches outside a closed room control three bulbs inside. You can open the door only once. How do you find which switch controls which bulb?',
    'A bulb tells you more than just on or off.',
    'Turn on switch 1 for a few minutes, turn it off, turn on switch 2, then go in. The lit bulb is 2, the warm dark bulb is 1, the cold dark bulb is 3.',
  ),
  Riddle(
    'Two ropes each take exactly 60 minutes to burn, but they burn unevenly. How can you measure 45 minutes?',
    'A rope lit at both ends burns out in half the time.',
    'Light rope A at both ends and rope B at one end. When A burns out (30 min), light the other end of B. It burns out 15 minutes later: 45 in total.',
  ),
  Riddle(
    'A father is four times as old as his son. In 20 years he will be twice as old as his son. How old is the son now?',
    'Write both ages 20 years from now.',
    '10. The father is 40; in 20 years they are 60 and 30.',
  ),
  Riddle(
    'What comes next: 1, 11, 21, 1211, 111221, …?',
    'Read each number out loud, digit by digit.',
    '312211. Each number describes the one before: 111221 is "three 1s, two 2s, one 1".',
  ),
  Riddle(
    'A surgeon looks at a boy and says, "I can\'t operate on him, he is my son." The surgeon is not the boy\'s father. How?',
    'Who else could be his parent?',
    'The surgeon is his mother.',
  ),
  Riddle(
    'You have 9 balls that look the same; one is slightly heavier. With a balance scale, what is the fewest weighings that always finds the heavy one?',
    'Split into three groups, not two.',
    '2. Weigh 3 against 3: the heavier side, or the 3 left out if they balance, holds it. Then weigh 1 against 1 from that group the same way.',
  ),
  Riddle(
    'A man pushes his car to a hotel and tells the owner he is bankrupt. Why?',
    'Not every car runs on petrol.',
    'He is playing a board game where you buy properties; his piece is a little car.',
  ),
  Riddle(
    'What gets wetter the more it dries?',
    'You use it after a bath.',
    'A towel.',
  ),
  Riddle(
    'Which is heavier: a kilogram of iron or a kilogram of cotton?',
    'Look at the units.',
    'Neither. Both weigh one kilogram.',
  ),
  Riddle(
    'A number is doubled, then 4 is added, and the result is 20. What was the number?',
    'Undo the steps in reverse order.',
    '8. Take away 4 to get 16, then halve it.',
  ),
];
