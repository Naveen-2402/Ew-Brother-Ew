import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens. Same hex values as android/.../overlay/OverlayStyle.kt and colors.xml.
///
/// Direction: a brinjal (aubergine) night palette with pista green for good,
/// haldi (turmeric) for warning and chilli red for bad. One family, Bricolage
/// Grotesque, whose condensed heavy cut carries the one loud element: the reel count.
@immutable
class EwColors extends ThemeExtension<EwColors> {
  const EwColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.text,
    required this.muted,
    required this.good,
    required this.warn,
    required this.bad,
    required this.insta,
    required this.shorts,
    required this.onAccent,
  });

  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color text;
  final Color muted;
  final Color good;
  final Color warn;
  final Color bad;
  final Color insta;
  final Color shorts;
  final Color onAccent;

  static const dark = EwColors(
    bg: Color(0xFF1C1524),
    surface: Color(0xFF271E31),
    surfaceHigh: Color(0xFF33283F),
    text: Color(0xFFF2ECE3),
    muted: Color(0xFFA99DB5),
    good: Color(0xFFA6E38E),
    warn: Color(0xFFFFB547),
    bad: Color(0xFFFF5E57),
    insta: Color(0xFFF58BB0),
    shorts: Color(0xFF8EC9FF),
    onAccent: Color(0xFF1C1524),
  );

  static const light = EwColors(
    bg: Color(0xFFF4F1F8),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFE9E3F0),
    text: Color(0xFF1C1524),
    muted: Color(0xFF6E6379),
    good: Color(0xFF3E8E3A),
    warn: Color(0xFFC46F00),
    bad: Color(0xFFD2392F),
    insta: Color(0xFFC2446F),
    shorts: Color(0xFF2E78C2),
    onAccent: Color(0xFFFFFFFF),
  );

  /// Green below 60% of the limit, orange to 85%, red after.
  Color progress(int reels, int limit) {
    final r = reels / (limit <= 0 ? 100 : limit);
    if (r < 0.6) return good;
    if (r < 0.85) return warn;
    return bad;
  }

  @override
  EwColors copyWith() => this;

  @override
  EwColors lerp(ThemeExtension<EwColors>? other, double t) {
    if (other is! EwColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return EwColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      good: l(good, other.good),
      warn: l(warn, other.warn),
      bad: l(bad, other.bad),
      insta: l(insta, other.insta),
      shorts: l(shorts, other.shorts),
      onAccent: l(onAccent, other.onAccent),
    );
  }
}

extension EwContext on BuildContext {
  EwColors get ew => Theme.of(this).extension<EwColors>()!;
  TextTheme get type => Theme.of(this).textTheme;
}

const _family = 'Bricolage';

FontWeight _nearest(double w) {
  const all = FontWeight.values; // w100..w900
  return all[((w / 100).round() - 1).clamp(0, all.length - 1)];
}

/// Bricolage is a variable font: weight, width and optical size are set as axes.
TextStyle ewText(
  double size,
  double weight, {
  double width = 100,
  Color? color,
  double? height,
  double? letterSpacing,
}) =>
    TextStyle(
      fontFamily: _family,
      fontSize: size,
      fontWeight: _nearest(weight),
      fontVariations: [
        FontVariation('wght', weight),
        FontVariation('wdth', width),
        FontVariation('opsz', size.clamp(12, 96).toDouble()),
      ],
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? EwColors.dark : EwColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.good,
    onPrimary: c.onAccent,
    secondary: c.warn,
    onSecondary: c.onAccent,
    error: c.bad,
    onError: c.onAccent,
    surface: c.bg,
    onSurface: c.text,
    surfaceContainerLowest: c.bg,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceHigh,
    surfaceContainerHighest: c.surfaceHigh,
    onSurfaceVariant: c.muted,
    outline: c.muted.withValues(alpha: 0.5),
    outlineVariant: c.surfaceHigh,
  );

  final text = TextTheme(
    displayLarge: ewText(88, 800, width: 75, color: c.text, height: 0.9, letterSpacing: -2),
    headlineMedium: ewText(28, 720, color: c.text, height: 1.1),
    headlineSmall: ewText(22, 680, color: c.text, height: 1.15),
    titleLarge: ewText(20, 650, color: c.text),
    titleMedium: ewText(16, 600, color: c.text),
    titleSmall: ewText(14, 600, color: c.muted),
    bodyLarge: ewText(16, 420, color: c.text, height: 1.35),
    bodyMedium: ewText(14, 420, color: c.text, height: 1.35),
    bodySmall: ewText(12.5, 450, color: c.muted, height: 1.3),
    labelLarge: ewText(15, 620, color: c.text),
    labelMedium: ewText(13, 560, color: c.muted),
    labelSmall: ewText(11.5, 560, color: c.muted),
  );

  final stadium = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    fontFamily: _family,
    textTheme: text,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: ewText(20, 680, color: c.text),
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.good.withValues(alpha: 0.22),
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => ewText(12.5, s.contains(WidgetState.selected) ? 650 : 480,
            color: s.contains(WidgetState.selected) ? c.text : c.muted),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.text : c.muted),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        shape: stadium,
        textStyle: WidgetStatePropertyAll(ewText(15, 640)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        shape: stadium,
        side: WidgetStatePropertyAll(BorderSide(color: c.surfaceHigh, width: 2)),
        foregroundColor: WidgetStatePropertyAll(c.text),
        textStyle: WidgetStatePropertyAll(ewText(15, 620)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        foregroundColor: WidgetStatePropertyAll(c.good),
        textStyle: WidgetStatePropertyAll(ewText(15, 620)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onAccent : c.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.good : c.surfaceHigh,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.good,
      inactiveTrackColor: c.surfaceHigh,
      thumbColor: c.good,
      overlayColor: c.good.withValues(alpha: 0.12),
      valueIndicatorColor: c.surfaceHigh,
      valueIndicatorTextStyle: ewText(14, 620, color: c.text),
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: ewText(16, 420, color: c.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: c.good, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surfaceHigh,
      contentTextStyle: ewText(14.5, 480, color: c.text),
      actionTextColor: c.good,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.surfaceHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.good : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onAccent : c.text,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: c.surfaceHigh, width: 1.5)),
        textStyle: WidgetStatePropertyAll(ewText(14, 600)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: 12,
      titleTextStyle: ewText(16, 540, color: c.text),
      subtitleTextStyle: ewText(13.5, 420, color: c.muted),
      iconColor: c.muted,
    ),
    dividerTheme: DividerThemeData(color: c.surfaceHigh, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.good, linearTrackColor: c.surfaceHigh),
  );
}
