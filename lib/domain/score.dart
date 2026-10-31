/// F11 daily score, 0 to 100.
///
/// Habits done (weight 40), top tasks done (30) and reels (30, full marks at 0 reels,
/// zero at the limit). Parts with nothing to measure (no habits, no tasks) are left
/// out and the rest are scaled up, so an empty day isn't punished.
int dailyScore({
  required int habitsDone,
  required int habitsTotal,
  required int topDone,
  required int topTotal,
  required int reels,
  required int limit,
}) {
  var weight = 0.0;
  var points = 0.0;
  if (habitsTotal > 0) {
    weight += 40;
    points += 40 * habitsDone / habitsTotal;
  }
  if (topTotal > 0) {
    weight += 30;
    points += 30 * topDone / topTotal;
  }
  weight += 30;
  points += 30 * (1 - (reels / (limit <= 0 ? 100 : limit)).clamp(0.0, 1.0));
  return (100 * points / weight).round().clamp(0, 100);
}

/// Brain mood thresholds from the spec: 0, 50, 100, 200 reels.
enum BrainMood { fresh, meh, melting, fried }

BrainMood moodFor(int reels) {
  if (reels >= 200) return BrainMood.fried;
  if (reels >= 100) return BrainMood.melting;
  if (reels >= 50) return BrainMood.meh;
  return BrainMood.fresh;
}

String moodLine(BrainMood m) => switch (m) {
      BrainMood.fresh => 'Brain: fresh',
      BrainMood.meh => 'Brain: getting mushy',
      BrainMood.melting => 'Brain: melting',
      BrainMood.fried => 'Brain: fried. Ew.',
    };
