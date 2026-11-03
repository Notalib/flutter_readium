import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

/// How long after an internal link a position change still counts as its jump.
const _jumpWindow = Duration(seconds: 1);

/// Positions to return to after the reader followed an internal link.
class ReturnStack extends ChangeNotifier {
  ReturnStack() {
    _sub = FlutterReadium().onTextLocatorChanged.listen(_onLocatorChanged);
  }

  final _positions = <Locator>[];
  late final StreamSubscription<Locator> _sub;
  Locator? _pending;
  DateTime? _pendingAt;

  bool get canReturn => _positions.isNotEmpty;

  /// Only remembers [InternalLinkEvent.from] once the position actually changes,
  /// so links to a target that is already on screen add nothing.
  void onLinkActivated(final InternalLinkEvent event) {
    _pending = event.from;
    _pendingAt = DateTime.now();
  }

  Future<void> returnToPrevious() {
    final locator = _positions.removeLast();
    notifyListeners();
    return FlutterReadium().goToLocator(locator);
  }

  void _onLocatorChanged(final Locator locator) {
    // The user got back to a remembered position by hand.
    if (canReturn && _samePosition(_positions.last, locator)) _positions.removeLast();

    final from = _pending;
    if (from != null) {
      if (DateTime.now().difference(_pendingAt!) > _jumpWindow) {
        _pending = null;
      } else if (!_samePosition(from, locator)) {
        _pending = null;
        if (!canReturn || !_samePosition(_positions.last, from)) _positions.add(from);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

bool _samePosition(final Locator a, final Locator b) =>
    a.href == b.href && ((a.locations?.progression ?? 0) - (b.locations?.progression ?? 0)).abs() < 0.001;

class ReturnToPreviousPositionButton extends StatelessWidget {
  const ReturnToPreviousPositionButton({required this.returnStack, super.key});

  final ReturnStack returnStack;

  @override
  Widget build(final BuildContext context) => ListenableBuilder(
    listenable: returnStack,
    builder: (final context, _) {
      if (!returnStack.canReturn) return const SizedBox.shrink();
      return FloatingActionButton.extended(
        key: const ValueKey('return_to_previous_position_button'),
        heroTag: null,
        icon: const Icon(Icons.undo),
        label: const Text('Return to previous position'),
        onPressed: returnStack.returnToPrevious,
      );
    },
  );
}
