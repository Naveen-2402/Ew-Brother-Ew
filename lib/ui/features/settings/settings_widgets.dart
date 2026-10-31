import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Slider that saves on release (no DB write per drag frame).
class SliderTile extends StatefulWidget {
  const SliderTile({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onSaved,
    this.enabled = true,
  });

  final String title;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final String Function(int v) label;
  final ValueChanged<int> onSaved;
  final bool enabled;

  @override
  State<SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<SliderTile> {
  late double _v = widget.value.toDouble();

  @override
  void didUpdateWidget(SliderTile old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(widget.title, style: context.type.bodyLarge)),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(widget.label(_v.round()), style: context.type.labelLarge),
              ),
            ],
          ),
          Slider(
            value: _v.clamp(widget.min.toDouble(), widget.max.toDouble()),
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.divisions,
            label: widget.label(_v.round()),
            onChanged: widget.enabled ? (v) => setState(() => _v = v) : null,
            onChangeEnd: widget.enabled ? (v) => widget.onSaved(v.round()) : null,
          ),
        ],
      ),
    );
  }
}

/// A row with a title and a segmented choice underneath.
class ChoiceTile<T> extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.type.bodyLarge),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: [
                for (final e in options.entries) ButtonSegment<T>(value: e.key, label: Text(e.value)),
              ],
              selected: {value},
              onSelectionChanged: (s) => onChanged(s.first),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grouped block of settings rows on a raised surface.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
          child: Text(title, style: context.type.titleSmall),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: context.ew.surface, borderRadius: BorderRadius.circular(22)),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      ],
    );
  }
}
