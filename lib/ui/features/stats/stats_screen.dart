import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/logical_day.dart';
import '../../../domain/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'stats_view_model.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StatsViewModel>();
    final c = context.ew;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: vm.load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('Stats', style: context.type.headlineMedium),
            ),
            const SectionTitle('Reels, last 7 days'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _Figure(value: '${vm.weekTotal}', label: 'this week'),
                  const SizedBox(width: 28),
                  _Figure(value: '${vm.weekAverage}', label: 'a day on average'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(height: 200, child: vm.loaded ? _ReelsChart(week: vm.week) : null),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  _Legend(color: c.insta, label: 'Instagram Reels'),
                  const SizedBox(width: 18),
                  _Legend(color: c.shorts, label: 'YouTube Shorts'),
                ],
              ),
            ),
            const SectionTitle('Top apps today'),
            if (vm.loaded && vm.topApps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('No screen time yet. Usage access may be off.',
                    style: context.type.bodyMedium?.copyWith(color: c.muted)),
              )
            else
              _TopApps(apps: vm.topApps),
            const SectionTitle('Screen time trend'),
            SizedBox(
              height: 180,
              child: vm.loaded ? _ScreenTrend(days: vm.week.map((d) => d.date).toList(), seconds: vm.screenWeek) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: ewText(34, 800, width: 78, color: context.ew.text, height: 1)),
        Text(label, style: context.type.bodySmall),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: context.type.bodySmall),
      ],
    );
  }
}

String _dayLetter(String key) => weekdayShort[LogicalDay.parse(key).weekday - 1];

/// Stacked bars: Instagram at the bottom, YouTube on top.
class _ReelsChart extends StatelessWidget {
  const _ReelsChart({required this.week});

  final List<ReelDay> week;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final maxTotal = week.fold<int>(0, (m, d) => math.max(m, d.total));
    final maxY = maxTotal == 0 ? 10.0 : (maxTotal * 1.2).ceilToDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: math.max(1.0, maxY / 4),
            getDrawingHorizontalLine: (_) => FlLine(color: c.surfaceHigh, strokeWidth: 1, dashArray: const [4, 4]),
          ),
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
                  if (i < 0 || i >= week.length) return const SizedBox.shrink();
                  final isToday = i == week.length - 1;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      isToday ? 'Today' : _dayLetter(week[i].date),
                      style: context.type.labelSmall?.copyWith(color: isToday ? c.text : c.muted),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => c.surfaceHigh,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final d = week[groupIndex];
                return BarTooltipItem(
                  '${d.total} reels\n',
                  ewText(14, 680, color: c.text),
                  children: [
                    TextSpan(
                      text: '${d.instagram} Reels, ${d.youtube} Shorts',
                      style: ewText(12, 460, color: c.muted),
                    ),
                  ],
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < week.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: week[i].total.toDouble(),
                    width: 22,
                    color: week[i].total == 0 ? c.surfaceHigh : c.shorts,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                    rodStackItems: week[i].total == 0
                        ? null
                        : [
                            BarChartRodStackItem(0, week[i].instagram.toDouble(), c.insta),
                            BarChartRodStackItem(
                              week[i].instagram.toDouble(),
                              week[i].total.toDouble(),
                              c.shorts,
                            ),
                          ],
                  ),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 200),
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
    final max = apps.isEmpty ? 1 : apps.first.seconds;
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
                      Expanded(
                        child: Text(a.label, style: context.type.bodyLarge, overflow: TextOverflow.ellipsis),
                      ),
                      Text(formatDuration(a.seconds), style: context.type.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: a.seconds / max,
                      minHeight: 6,
                      color: _appColor(c, a.package),
                      backgroundColor: c.surfaceHigh,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _appColor(EwColors c, String pkg) => switch (pkg) {
        'com.instagram.android' => c.insta,
        'com.google.android.youtube' => c.shorts,
        _ => c.muted,
      };
}

class _ScreenTrend extends StatelessWidget {
  const _ScreenTrend({required this.days, required this.seconds});

  final List<String> days;
  final List<int> seconds;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final hours = [for (final s in seconds) s / 3600];
    final maxH = hours.fold<double>(0, math.max);
    final maxY = maxH == 0 ? 4.0 : (maxH * 1.25).ceilToDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 24, 0),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          minX: 0,
          maxX: (days.length - 1).toDouble(),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: math.max(1.0, maxY / 4),
            getDrawingHorizontalLine: (_) => FlLine(color: c.surfaceHigh, strokeWidth: 1, dashArray: const [4, 4]),
          ),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: math.max(1.0, maxY / 4),
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text('${value.toStringAsFixed(0)}h', style: context.type.labelSmall),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= days.length || value != i.toDouble()) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      i == days.length - 1 ? 'Today' : _dayLetter(days[i]),
                      style: context.type.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => c.surfaceHigh,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(formatDuration(seconds[s.x.toInt()]), ewText(13, 620, color: c.text)),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < hours.length; i++) FlSpot(i.toDouble(), hours[i])],
              isCurved: true,
              preventCurveOverShooting: true,
              color: c.good,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: c.good.withValues(alpha: 0.12)),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 200),
      ),
    );
  }
}
