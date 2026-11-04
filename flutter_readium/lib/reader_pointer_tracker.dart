import 'dart:ui';

/// Internal use only.
/// Turns the raw pointer stream above the native reader into controls and narration signals.
///
/// Reader paths that report native tap feedback ([nativeTapFeedback]) classify taps natively, so
/// only drags are handled here. Other readers keep the legacy edge/center tap classification.
class ReaderPointerTracker {
  ReaderPointerTracker({
    required this.onDeliberateDrag,
    required this.onUserNavigation,
    required this.onEdgeTap,
    required this.onCenterTap,
  });

  /// A drag past the pan slop. Hides active controls; never changes narration following.
  final void Function() onDeliberateDrag;

  /// The user took manual control of navigation (narration manual mode).
  final void Function() onUserNavigation;

  /// Legacy tap near a screen edge. Only reported while [nativeTapFeedback] is false.
  final void Function() onEdgeTap;

  /// Legacy tap away from the edges. Only reported while [nativeTapFeedback] is false.
  final void Function() onCenterTap;

  /// Edge width for the legacy tap classification, in logical pixels.
  static const legacyEdgeWidth = 70.0;

  /// Whether the native reader reports taps itself.
  bool nativeTapFeedback = false;

  /// Scroll mode. Native readers then enter manual mode from a single-pointer reading-axis drag,
  /// because scrolling gives no native navigation outcome to observe.
  bool scrollMode = false;

  final Map<int, _Pointer> _activePointers = {};
  bool _didSequenceMove = false;
  bool _didSequenceMultiTouch = false;
  bool _didHideForDrag = false;
  bool _didNotifyNavigation = false;

  void down(
    final int pointer,
    final Offset origin, {
    required final double tapSlop,
    required final double panSlop,
  }) {
    final hadActivePointers = _activePointers.isNotEmpty;
    if (!hadActivePointers) {
      _resetSequence();
    }

    _activePointers[pointer] = _Pointer(origin: origin, tapSlop: tapSlop, panSlop: panSlop);

    if (hadActivePointers) {
      _didSequenceMove = true;
      _didSequenceMultiTouch = true;
      _hideForDrag();
      // A second pointer is no reading-axis scroll, so scroll mode keeps following.
      if (!(nativeTapFeedback && scrollMode)) {
        _notifyNavigation();
      }
    }
  }

  void move(final int pointer, final Offset position) {
    final state = _activePointers[pointer];
    if (state == null) {
      return;
    }

    final delta = position - state.origin;
    if (delta.distance > state.tapSlop) {
      _didSequenceMove = true;
    }
    if (delta.distance > state.panSlop) {
      _hideForDrag();
      if (!(nativeTapFeedback && scrollMode)) {
        _notifyNavigation();
      }
    }
    if (nativeTapFeedback &&
        scrollMode &&
        !_didSequenceMultiTouch &&
        delta.dy.abs() > state.panSlop &&
        delta.dy.abs() > delta.dx.abs()) {
      _notifyNavigation();
    }
  }

  void up(final int pointer, final Offset position, {required final double width}) {
    if (_activePointers.remove(pointer) == null || _activePointers.isNotEmpty) {
      return;
    }

    final didSequenceMove = _didSequenceMove;
    _resetSequence();
    if (didSequenceMove || nativeTapFeedback) {
      return;
    }

    if (position.dx < legacyEdgeWidth || (width - position.dx) < legacyEdgeWidth) {
      onEdgeTap();
    } else {
      onCenterTap();
    }
  }

  void cancel(final int pointer) {
    if (_activePointers.remove(pointer) != null && _activePointers.isEmpty) {
      _resetSequence();
    }
  }

  void _resetSequence() {
    _didSequenceMove = false;
    _didSequenceMultiTouch = false;
    _didHideForDrag = false;
    _didNotifyNavigation = false;
  }

  void _hideForDrag() {
    if (_didHideForDrag) {
      return;
    }
    _didHideForDrag = true;
    onDeliberateDrag();
  }

  void _notifyNavigation() {
    if (_didNotifyNavigation) {
      return;
    }
    _didNotifyNavigation = true;
    onUserNavigation();
  }
}

class _Pointer {
  const _Pointer({required this.origin, required this.tapSlop, required this.panSlop});

  final Offset origin;
  final double tapSlop;
  final double panSlop;
}
