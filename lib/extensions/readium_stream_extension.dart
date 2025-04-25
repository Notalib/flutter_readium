library;

import '../_index.dart';

extension ReadiumStreamExtension<T> on Stream<T> {
  Stream<T> get takeUntilPublicationChanged => TakeUntilExtension(this)
      .takeUntil(FlutterReadium.stateStream.readiumPublicationChanged)
      .asBroadcastStream();
}
