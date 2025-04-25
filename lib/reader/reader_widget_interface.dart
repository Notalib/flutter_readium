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

  Future<Locator?> getLocatorFragments(final Locator locator);
}
