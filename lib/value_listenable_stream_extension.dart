import 'dart:async';

import 'package:flutter/foundation.dart';

extension ValueListenableStreamExtension<T> on ValueListenable<T> {
  /// Creates a single-subscriber Stream which reports changes to this ValueListenable.
  Stream<T> asStream() {
    late final StreamController<T> r;
    void update() => r.add(value);
    void sub() => addListener(update);
    void unsub() => removeListener(update);
    r = StreamController(onListen: sub, onPause: unsub, onResume: sub, onCancel: unsub);
    return r.stream;
  }
}
