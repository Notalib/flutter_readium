import '../index.dart';

abstract class ReadiumReaderWidgetInterface {
  /// Call to navigate the reader to a location.
  Future<void> go(final Locator locator, {required final bool isAudioBookWithText, final bool animated = false});

  /// Go to previous page.
  Future<void> goBackward({final bool animated = true});

  /// Go to next page.
  Future<void> goForward({final bool animated = true});

  /// Set EPUB preferences
  Future<void> setEPUBPreferences(EPUBPreferences preferences);

  /// Apply decorations
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations);
}
