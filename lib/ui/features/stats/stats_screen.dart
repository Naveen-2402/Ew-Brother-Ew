import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/logical_day.dart';
import '../../../data/repositories.dart';
import '../../../domain/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'day_sheet.dart';
import 'stats_view_model.dart';

/// Stats and history: pick a range (presets or custom dates), pick what to look at,
/// read the summary, then scan or open any single day.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StatsViewModel>();
    final records = vm.records;
    final n = records.length;
    final maxValue = records.fold<int>(0, (m, r) => math.max(m, vm.value(r)));

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: vm.load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(vm: vm)),
            SliverToBoxAdapter(child: _RangeChips(vm: vm)),
            SliverToBoxAdapter(child: _MetricTabs(vm: vm)),
            SliverToBoxAdapter(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: vm.metric == Metric.reels ? _AppFilterRow(vm: vm) : const SizedBox(width: double.infinity),
              ),
            ),
            SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                child: _Summary(key: ValueKey('${vm.metric}-${vm.appFilter}-${vm.from}-${vm.to}'), vm: vm),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: 220, child: vm.loaded ? _HistoryChart(vm: vm) : null),
            ),
            SliverToBoxAdapter(child: _Extremes(vm: vm)),
            if (vm.metric == Metric.reels && vm.appFilter == AppFilter.all) SliverToBoxAdapter(child: _Split(vm: vm)),
            if (vm.metric == Metric.screen) ...[
              const SliverToBoxAdapter(child: SectionTitle('Most used apps')),
              SliverToBoxAdapter(
                child: vm.loaded && vm.topApps.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'No screen time stored for these days. Usage access may be off.',
                          style: context.type.bodyMedium?.copyWith(color: context.ew.muted),
                        ),
                      )
                    : _TopApps(apps: vm.topApps),
              ),
            ],
            SliverToBoxAdapter(
              child: SectionTitle(
                'Day by day',
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('Tap a day for details', style: context.type.bodySmall),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: n,
              itemBuilder: (context, i) {
                final r = records[n - 1 - i]; // newest first
                return FadeSlideIn(
                  key: ValueKey('${vm.from}-${r.date}'),
                  index: i,
                  child: _DayRow(vm: vm, record: r, maxValue: maxValue),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

String _fmt(StatsViewModel vm, int v) => vm.metric == Metric.screen ? formatDuration(v) : '$v';

Color _metricColor(EwColors c, StatsViewModel vm) => switch (vm.metric) {
      Metric.reels => switch (vm.appFilter) {
          AppFilter.instagram => c.insta,
          AppFilter.youtube => c.shorts,
          AppFilter.all => c.text,
        },
      Metric.screen => c.text,
      Metric.habits => c.good,
      Metric.tasks => c.warn,
    };

bool _beforeTracking(StatsViewModel vm, DayRecord r) => !vm.isTracked(r);

// ------------------------------------------------------------------ header and filters

class _Header extends StatelessWidget {
  const _Header({required this.vm});

  final StatsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final sameYear = vm.from.substring(0, 4) == vm.to.substring(0, 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('Stats', style: context.type.headlineMedium),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${formatShortDate(vm.from, withYear: !sameYear)} – ${formatShortDate(vm.to, withYear: !sameYear)}',
                style: context.type.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: vm.busy ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeChips extends StatelessWidget {
  const _RangeChips({required this.vm});

  final StatsViewModel vm;

  Future<void> _pickCustom(BuildContext context) async {
    final today = LogicalDay.parse(vm.today);
    final initial = DateTimeRange(start: LogicalDay.parse(vm.from), end: LogicalDay.parse(vm.to));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      currentDate: today,
      initialDateRange: initial,
      helpText: 'Pick the days to look at',
      saveText: 'Show',
    );
    if (picked == null) return;
    var start = picked.start;
    final end = picked.end;
    if (end.difference(start).inDays >= StatsViewModel.maxDays) {
      start = DateTime(end.year, end.month, end.day - (StatsViewModel.maxDays - 1));
      if (context.mounted) showSnack(context, 'Up to ${StatsViewModel.maxDays} days at a time. Showing the latest.');
    }
    vm.setCustom(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final custom = vm.preset == RangePreset.custom;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          for (final p in RangePreset.values.where((p) => p != RangePreset.custom)) ...[
            _Chip(label: p.label, selected: vm.preset == p, onTap: () => vm.setPreset(p)),
            const SizedBox(width: 8),
          ],
          _Chip(
            label: custom ? '${formatShortDate(vm.from)} – ${formatShortDate(vm.to)}' : 'Custom',
            icon: Icons.calendar_month_rounded,
            selected: custom,
            onTap: () => _pickCustom(context),
          ),
        ],
      ),
    );
  }
}

/// Filter chip: outlined when off, solid ink when on.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.icon, this.dot});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final fg = selected ? c.bg : c.text;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? c.text : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? c.text : c.surfaceHigh, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 7),
              ],
              if (icon != null) ...[
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: ewText(14, selected ? 680 : 540, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricTabs extends StatelessWidget {
  const _MetricTabs({required this.vm});

  final StatsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          for (final m in Metric.values)
            Semantics(
              button: true,
              selected: vm.metric == m,
              child: InkWell(
                onTap: () => vm.setMetric(m),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        style: ewText(17, vm.metric == m ? 740 : 520, color: vm.metric == m ? c.text : c.muted),
                        child: Text(m.label),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        width: vm.metric == m ? 22 : 0,
                        height: 3,
                        decoration: BoxDecoration(color: c.good, borderRadius: BorderRadius.circular(2)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppFilterRow extends StatelessWidget {
  const _AppFilterRow({required this.vm});

  final StatsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in AppFilter.values)
            _Chip(
              label: f.label,
              selected: vm.appFilter == f,
              dot: switch (f) {
                AppFilter.all => null,
                AppFilter.instagram => c.insta,
                AppFilter.youtube => c.shorts,
              },
              onTap: () => vm.setAppFilter(f),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ summary

class _Summary extends StatelessWidget {
  const _Summary({super.key, required this.vm});

  final StatsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final pct = vm.changePercent;
    Widget rule() => Container(width: 1, height: 38, color: c.surfaceHigh);

    final Widget first = vm.metric == Metric.habits
        ? _Big(value: '${vm.habitRate}%', label: 'of habits done', color: c.good)
        : _Big(value: _fmt(vm, vm.total), label: 'in total');

    final Widget change;
    if (pct == null) {
      change = const _Big(value: '–', label: 'not enough earlier data');
    } else {
      final better = vm.metric.lowerIsBetter ? pct < 0 : pct > 0;
      final color = pct == 0 ? c.muted : (better ? c.good : c.bad);
      final arrow = pct > 0 ? '↑' : (pct < 0 ? '↓' : '');
      change = _Big(value: '$arrow${pct.abs()}%', label: 'a day, vs previous ${vm.records.length} days', color: color);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: c.surfaceHigh))),
      child: Row(
        children: [
          Expanded(child: first),
          rule(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: _Big(value: _fmt(vm, vm.average), label: 'a day on average'),
            ),
          ),
          rule(),
          Expanded(child: Padding(padding: const EdgeInsets.only(left: 14), child: change)),
        ],
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: ewText(26, 780, width: 80, height: 1.1, color: color ?? context.ew.text)),
        ),
        const SizedBox(height: 2),
        Text(label, style: context.type.bodySmall, maxLines: 2),
      ],
    );
  }
}

// ------------------------------------------------------------------ chart

/// One bar per day, or per week when the range is longer than ~3 months (so bars stay tappable).
class _HistoryChart extends StatelessWidget {
  const _HistoryChart({required this.vm});

  final StatsViewModel vm;

  /// Ranges longer than this are drawn as weekly bars.
  static const _dailyLimit = 92;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final records = vm.records;
    if (records.isEmpty) return const SizedBox.shrink();

    // Buckets, oldest first. Weekly buckets are counted back from the newest day,
    // so the last bar always ends on the last day of the range.
    final weekly = records.length > _dailyLimit;
    final buckets = <List<DayRecord>>[];
    if (weekly) {
      for (var end = records.length; end > 0; end -= 7) {
        buckets.insert(0, records.sublist(math.max(0, end - 7), end));
      }
    } else {
      for (final r in records) {
        buckets.add([r]);
      }
    }
    final n = buckets.length;
    final last = n - 1;
    final isScreen = vm.metric == Metric.screen;
    int sum(List<DayRecord> b) => b.fold(0, (s, r) => s + vm.value(r));
    double y(List<DayRecord> b) => isScreen ? sum(b) / 3600 : sum(b).toDouble();

    final maxV = buckets.fold<double>(0, (m, b) => math.max(m, y(b)));
    final fallback = switch (vm.metric) {
      Metric.reels => 10.0,
      Metric.screen => 4.0,
      Metric.habits => math.max(1, records.last.habitsTotal).toDouble(),
      Metric.tasks => 5.0,
    };
    final maxY = maxV == 0 ? fallback : maxV * 1.15;
    final step = (n / 7).ceil();
    final stacked = vm.metric == Metric.reels && vm.appFilter == AppFilter.all;
    final color = _metricColor(c, vm);

    String label(int i) {
      final first = buckets[i].first.date;
      if (!weekly && first == vm.today) return 'Today';
      if (!weekly && n <= 7) return weekdayShort[LogicalDay.parse(first).weekday - 1];
      return formatShortDate(first);
    }

    String tooltipTitle(List<DayRecord> b) => weekly
        ? '${formatShortDate(b.first.date)} – ${formatShortDate(b.last.date)}'
        : formatDayKey(b.first.date, vm.today);

    return LayoutBuilder(
      builder: (context, box) {
        final barW = ((box.maxWidth - 24) / n * 0.62).clamp(2.0, 18.0);
        final radius = Radius.circular(math.min(4.0, barW / 2));
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= n || (last - i) % step != 0) return const SizedBox.shrink();
                      final current = buckets[i].any((r) => r.date == vm.today);
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          label(i),
                          style: context.type.labelSmall?.copyWith(color: current ? c.text : c.muted),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchCallback: (event, response) {
                  final spot = response?.spot;
                  // Tapping a daily bar opens that day; weekly bars just show their tooltip.
                  if (!weekly && event is FlTapUpEvent && spot != null) {
                    showDaySheet(context, buckets[spot.touchedBarGroupIndex].first);
                  }
                },
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => c.surfaceHigh,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final b = buckets[groupIndex];
                    return BarTooltipItem(
                      '${tooltipTitle(b)}\n',
                      ewText(12, 520, color: c.muted),
                      children: [TextSpan(text: _fmt(vm, sum(b)), style: ewText(15, 720, color: c.text))],
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < n; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: y(buckets[i]),
                        width: barW,
                        color: y(buckets[i]) == 0
                            ? c.surfaceHigh
                            : (i == last || stacked ? color : color.withValues(alpha: 0.72)),
                        borderRadius: BorderRadius.vertical(top: radius),
                        rodStackItems: !stacked || y(buckets[i]) == 0
                            ? null
                            : () {
                                final ig = buckets[i].fold<int>(0, (s, r) => s + r.reels.instagram).toDouble();
                                final all = buckets[i].fold<int>(0, (s, r) => s + r.reels.total).toDouble();
                                return [
                                  BarChartRodStackItem(0, ig, c.insta),
                                  BarChartRodStackItem(ig, all, c.shorts),
                                ];
                              }(),
                      ),
                    ],
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ extras

class _Extremes extends StatelessWidget {
  const _Extremes({required this.vm});

  final StatsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final e = vm.extremes;
    final best = e.best;
    final worst = e.worst;
    if (best == null || worst == null) return const SizedBox(height: 4);
    final c = context.ew;
    Widget row(String label, DayRecord r, Color color) => InkWell(
          onTap: () => showDaySheet(context, r),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                SizedBox(width: 82, child: Text(label, style: context.type.bodySmall)),
                Expanded(child: Text(formatDayKey(r.date, vm.today), style: context.type.bodyLarge)),
                Text(_fmt(vm, vm.value(r)), style: context.type.labelLarge),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          row('Best day', best, c.good),
          row('Worst day', worst, c.bad),
        ],
      ),
    );
  }
}

/// Instagram vs YouTube share of the range.
class _Split extends StatelessWidget {
  const _Split({required this.vm});

  final StatsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final ig = vm.instagramTotal;
    final yt = vm.youtubeTotal;
    if (ig + yt == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Instagram ', style: context.type.labelMedium),
              Text('$ig', style: context.type.labelLarge?.copyWith(color: c.insta)),
              const Spacer(),
              Text('YouTube ', style: context.type.labelMedium),
              Text('$yt', style: context.type.labelLarge?.copyWith(color: c.shorts)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (ig > 0) Expanded(flex: ig, child: ColoredBox(color: c.insta)),
                  if (ig > 0 && yt > 0) const SizedBox(width: 2),
                  if (yt > 0) Expanded(flex: yt, child: ColoredBox(color: c.shorts)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopApps extends StatelessWidget {
  const _TopApps({required this.apps});

  final List<AppUsageEntry> apps;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final max = apps.isEmpty ? 1 : math.max(1, apps.first.seconds);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (final a in apps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(a.label, style: context.type.bodyLarge, overflow: TextOverflow.ellipsis)),
                      Text(formatDuration(a.seconds), style: context.type.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: a.seconds / max),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: v,
                        minHeight: 5,
                        color: appColor(c, a.package),
                        backgroundColor: c.surfaceHigh,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Color appColor(EwColors c, String pkg) => switch (pkg) {
      'com.instagram.android' => c.insta,
      'com.google.android.youtube' => c.shorts,
      _ => c.muted,
    };

class _DayRow extends StatelessWidget {
  const _DayRow({required this.vm, required this.record, required this.maxValue});

  final StatsViewModel vm;
  final DayRecord record;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final v = vm.value(record);
    final untracked = _beforeTracking(vm, record);
    final color = _metricColor(c, vm);
    final isToday = record.date == vm.today;
    return InkWell(
      onTap: () => showDaySheet(context, record),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text(
                formatDayKey(record.date, vm.today),
                style: context.type.bodyLarge?.copyWith(
                  color: untracked ? c.muted : c.text,
                  fontWeight: isToday ? FontWeight.w700 : null,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: maxValue == 0 || untracked ? 0.02 : math.max(0.02, v / maxValue),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: v == 0 || untracked ? c.surfaceHigh : color.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 84,
              child: Text(
                untracked ? '–' : (vm.metric == Metric.habits ? '$v of ${record.habitsTotal}' : _fmt(vm, v)),
                textAlign: TextAlign.right,
                style: context.type.labelLarge?.copyWith(color: untracked ? c.muted : c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
