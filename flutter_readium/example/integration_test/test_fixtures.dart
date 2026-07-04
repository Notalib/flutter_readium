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
  /// Lightweight reflowable EPUB3 (Nota's *De nye læsere*, Danish) used as the
  /// workhorse for navigation / search / decoration tests. 8 small spine
  /// documents (2.5–26 KB), so pagination and cross-resource navigation are
  /// cheap — far better suited to automated tests than a single-huge-resource
  /// book. Available on native (.epub) and web (test-fixtures/ebook).
  static const reflowableEpub = '712199_ebook.epub';

  /// Illustrated EPUB (Beatrix Potter's *The Tale of Peter Rabbit*, Project
  /// Gutenberg #14838) used for image-tap and getResourceUrl tests. Contains
  /// ~29 image resources (cover + interior plates) detectable via the manifest
  /// resources list.
  static const peterRabbitEpub = 'peter_rabbit.epub';

  /// Synthetic single-page Peter Rabbit webpub — the lightest publication in the
  /// suite (one 789-byte page + a couple of images). Used only to warm up the
  /// reader platform view. Available on native (.webpub) and web
  /// (test-fixtures/peter-rabbit).
  static const warmupWebpub = 'test-peter-rabbit.webpub';
  static const overlayWebpub = '38533_overlay_preview.webpub';
  static const audiobook = '38533.audiobook';
  static const pdfTest = 'pdf_test.pdf';
  static const timeMachinePdf = 'time_machine.pdf';
  static const divinaComicCbz = 'sample_comic.cbz';

  /// DiViNa image publication (web-only; served as a local exploded manifest).
  static const divina = '50272-nota-comics.divina';

  /// Remote audiobook manifest (manifest-only fixture; media stays remote).
  static const remoteAudiobook = 'flatland.json';

  /// Fixed-layout EPUB. Available on native (.webpub) and web
  /// (test-fixtures/fixed-layout).
  static const fixedLayout = 'test-fixed-layout.webpub';

  /// Guided-navigation publication. Available on native (.webpub) and web
  /// (test-fixtures/guided-navigation).
  static const guidedNav = '38533_guided_navigation_preview.webpub';

  /// Nota comic-book media-overlay EPUB. Available on native (.webpub) and web
  /// (test-fixtures/comic).
  static const comic = '50272-nota-comics.webpub';

  /// All fixture keys that should be available on web.
  static const web = {
    reflowableEpub,
    peterRabbitEpub,
    warmupWebpub,
    overlayWebpub,
    audiobook,
    divina,
    remoteAudiobook,
    fixedLayout,
    guidedNav,
    comic,
  };

  /// True when [key] is not expected to be available on web.
  static bool isUnavailableOnWeb(String key) => kIsWeb && !web.contains(key);
}
