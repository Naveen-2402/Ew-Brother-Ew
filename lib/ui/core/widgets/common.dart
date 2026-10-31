import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Section title used on every screen: plain sentence case, no eyebrow labels.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 12, 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: context.type.titleLarge)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Empty state: one short line and one button, never long text.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.line, required this.action, required this.onPressed});

  final String line;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(line, style: context.type.bodyLarge?.copyWith(color: context.ew.muted))),
          const SizedBox(width: 12),
          FilledButton.tonal(onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
  }
}

/// Longest task or habit name (keeps the widget and notifications readable).
const maxTitleLength = 120;

/// The haptic tick used when completing a task or habit.
void tickHaptic() => HapticFeedback.lightImpact();

/// Round check used by tasks: 48 dp tap target, fills green when done.
class CheckDot extends StatelessWidget {
  const CheckDot({super.key, required this.done, required this.onTap, this.color});

  final bool done;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final accent = color ?? c.good;
    return SizedBox.square(
      dimension: 48,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? accent : Colors.transparent,
              border: Border.all(color: done ? accent : c.muted, width: 2),
            ),
            child: done ? Icon(Icons.check_rounded, size: 18, color: c.onAccent) : null,
          ),
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String text, {String? action, VoidCallback? onAction}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 4),
      action: action == null ? null : SnackBarAction(label: action, onPressed: onAction ?? () {}),
    ),
  );
}

/// Fades and lifts a widget in once, the first time it is built.
/// [index] staggers siblings by 40 ms (capped so long lists don't wait).
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final delay = index.clamp(0, 8) * 40;
    const run = 260;
    final total = delay + run;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child),
      ),
      child: child,
    );
  }
}
