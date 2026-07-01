// Platform-aware fixture loader for integration tests.
//
// On native (iOS/Android): copies bundled assets to local storage and returns
// file paths.
// On web: returns URLs to publicly-hosted webpub manifests that the ts-toolkit
// can fetch directly.

import 'package:flutter/foundation.dart' show kIsWeb;

import 'test_fixtures_native.dart' if (dart.library.js_interop) 'test_fixtures_web.dart' as platform;

/// Returns a map of fixture name → path/URL suitable for the current platform.
Future<Map<String, String>> loadFixturePaths() => platform.loadFixturePaths();

/// Fixture keys used across tests. Keeping them here avoids typos.
abstract final class FixtureKeys {
  static const mobyDickEpub = 'moby_dick.epub';

  /// Illustrated EPUB (Beatrix Potter's *The Tale of Peter Rabbit*, Project
  /// Gutenberg #14838) used for image-tap and getResourceUrl tests. Contains
  /// ~29 image resources (cover + interior plates) detectable via the manifest
  /// resources list.
  static const peterRabbitEpub = 'peter_rabbit.epub';
  static const overlayWebpub = '38533_overlay_preview.webpub';
  static const audiobook = '38533.audiobook';
  static const pdfTest = 'pdf_test.pdf';
  static const timeMachinePdf = 'time_machine.pdf';

  /// Fixed-layout EPUB (web-only; served as a local exploded webpub).
  static const fixedLayout = 'fixed_layout.webpub';

  /// Guided-navigation publication (web-only; served as a local exploded webpub).
  static const guidedNav = 'guided_navigation.webpub';

  /// Nota comic-book media-overlay EPUB (web-only; served as a local exploded webpub).
  static const comic = 'comic.webpub';

  /// All fixture keys that should be available on web.
  static const web = {
    mobyDickEpub,
    overlayWebpub,
    audiobook,
    fixedLayout,
    guidedNav,
    comic,
  };

  /// True when [key] is not expected to be available on web.
  static bool isUnavailableOnWeb(String key) => kIsWeb && !web.contains(key);
}
