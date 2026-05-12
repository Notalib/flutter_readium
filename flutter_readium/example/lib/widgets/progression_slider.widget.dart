import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart' show Locator;

import '../state/index.dart';

class ProgressionSlider extends StatefulWidget {
  const ProgressionSlider({super.key});

  @override
  State<ProgressionSlider> createState() => _ProgressionSliderState();
}

class _ProgressionSliderState extends State<ProgressionSlider> {
  double? isDraggingSliderValue;

  /// Resolves a 0..1 resource progression from a [Locator].
  ///
  /// Readium's audio navigator populates `locations.progression` directly, but
  /// the EPUB navigator does not always — depending on platform and whether a
  /// positions list is available. As a fallback we derive it from the
  /// `currentPage`/`totalPages` additions made in `Locator.addPageNumber` on
  /// Android.
  double? _resolveProgression(final Locator? locator) {
    final locations = locator?.locations;
    if (locations == null) return null;

    if (locations.progression != null) return locations.progression;

    final currentPage = locations['currentPage'];
    final totalPages = locations['totalPages'];
    if (currentPage is int && totalPages is int && totalPages > 0) {
      return ((currentPage - 1) / totalPages).clamp(0.0, 1.0);
    }
    return null;
  }

  @override
  Widget build(final BuildContext context) => StreamBuilder<Locator>(
    stream: context.read<PlayerControlsBloc>().currentLocatorStream,
    builder: (final context, final snapshot) {
      final progression = _resolveProgression(snapshot.data) ?? 0.0;
      return Slider(
        value: isDraggingSliderValue ?? progression.clamp(0.0, 1.0),
        allowedInteraction: SliderInteraction.tapAndSlide,
        onChanged: (final double value) {
          setState(() => isDraggingSliderValue = value);
        },
        onChangeStart: (final double value) {
          setState(() => isDraggingSliderValue = value);
        },
        onChangeEnd: (final double value) {
          setState(() => isDraggingSliderValue = null);
          context.read<PlayerControlsBloc>().add(GoToProgression(value));
        },
      );
    },
  );
}
