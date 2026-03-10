import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AnimatedSlideOutWidget extends AnimatedWidget {
  const AnimatedSlideOutWidget({
    required final ValueListenable<bool> visible,
    required this.hiddenOffset,
    required this.duration,
    required this.child,
    super.key,
  }) : super(listenable: visible);

  final Offset hiddenOffset;
  final Duration duration;
  final Widget child;

  ValueListenable<bool> get visible => listenable as ValueListenable<bool>;

  @override
  Widget build(final BuildContext context) =>
      _AnimatedSlideOut(visible: visible.value, hiddenOffset: hiddenOffset, duration: duration, key: key, child: child);
}

class _AnimatedSlideOut extends StatefulWidget {
  const _AnimatedSlideOut({
    required this.visible,
    required this.hiddenOffset,
    required this.duration,
    required this.child,
    super.key,
  });

  final bool visible;
  final Offset hiddenOffset;
  final Duration duration;
  final Widget child;

  @override
  _AnimatedSlideOutState createState() => _AnimatedSlideOutState();
}

class _AnimatedSlideOutState extends State<_AnimatedSlideOut> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(value: widget.visible ? 0 : 1, duration: widget.duration, vsync: this);
  late final _easeIn = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
  late final _offset = Tween<Offset>(begin: Offset.zero, end: widget.hiddenOffset);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant final _AnimatedSlideOut oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    _offset.end = widget.hiddenOffset;
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.reverse();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) => _controller.value == 1
      ? const SizedBox.shrink()
      : FractionalTranslation(translation: _offset.evaluate(_easeIn), child: widget.child);
}
