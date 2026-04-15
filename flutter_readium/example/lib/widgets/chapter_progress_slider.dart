import 'package:flutter/material.dart';

class ChapterProgressSlider extends StatefulWidget {
  const ChapterProgressSlider({super.key, required this.value, required this.onChangeEnd});

  final double value;
  final ValueChanged<double> onChangeEnd;

  @override
  State<ChapterProgressSlider> createState() => _ChapterProgressSliderState();
}

class _ChapterProgressSliderState extends State<ChapterProgressSlider> {
  bool _isDragging = false;
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final displayedValue = (_isDragging ? _dragValue : widget.value)?.clamp(0.0, 1.0) ?? 0.0;

    return Slider.adaptive(
      value: displayedValue,
      onChangeStart: (v) => setState(() {
        _isDragging = true;
        _dragValue = v;
      }),
      onChanged: (v) => setState(() {
        _dragValue = v;
      }),
      onChangeEnd: (v) {
        setState(() {
          _isDragging = false;
          _dragValue = null;
        });
        widget.onChangeEnd(v.clamp(0.0, 1.0));
      },
    );
  }
}
