import '../_index.dart';

abstract class ReadiumReaderWidgetInterface {
  /// Call to go somewhere.
  Future<void> go(
    final Locator locator, {
    required final bool isAudioBookWithText,
    final bool animated = false,
  });

  /// Go to previous page.
  Future<void> goLeft({final bool animated = true});

  /// Go to next page.
  Future<void> goRight({final bool animated = true});

  /// Skip to previous chapter (toc)
  Future<void> skipToPrevious({final bool animated = true});

  /// Skip to next chapter (toc)
  Future<void> skipToNext({final bool animated = true});

  /// Gets the current Navigator's locator.
  Future<Locator?> getCurrentLocator();

  /// Get a locator with relevant fragments
  Future<Locator?> getLocatorFragments(final Locator locator);

  /// Set EPUB preferences
  Future<void> setEPUBPreferences(EPUBPreferences preferences);

  /// Apply decorations
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations);

  // TODO: Do we need a ReaderStatus as in current version?
  //Stream<ReadiumReaderStatus> get onReaderStatusChanged;

  Future<void> ttsStart(String langCode);
  Future<void> ttsStop();
}
