// Web fixture loader — returns URLs to webpub manifests the ts-toolkit
// HttpFetcher can fetch directly.
//
// Fixtures are served locally from `example/web/test-fixtures/` (Flutter copies
// the whole `web/` tree into the build output, so they resolve at the app origin
// during `flutter drive -d chrome`). Keeping them local removes the network
// dependency on external hosts and makes CI deterministic. They are generated
// (exploded + trimmed) from the readium-test-resources repo — see
// `CONTRIBUTING.md#test-fixtures`.
//
Future<Map<String, String>> loadFixturePaths() async {
  return const {
    // Reflowable workhorse (Nota's *De nye læsere*) — the same 712199_ebook
    // source the native suite opens as `.epub`, here served as a local exploded
    // webpub. Keeping it local (rather than a remote book) makes the shared EPUB
    // navigation tests deterministic on web too.
    '712199_ebook.epub': '/test-fixtures/ebook/manifest.json',

    // Synthetic single-page webpub used to warm up the reader platform view.
    'test-peter-rabbit.webpub': '/test-fixtures/peter-rabbit/manifest.json',

    // EPUB with media overlays (trimmed, local) — synced audio + text.
    '38533_overlay_preview.webpub': '/test-fixtures/overlay/manifest.json',

    // Audiobook (trimmed, local) — audio-only playback.
    '38533.audiobook': '/test-fixtures/audiobook/manifest.json',

    // Fixed-layout EPUB (local) — authored public-domain FXL test book.
    'fixed_layout.webpub': '/test-fixtures/fixed-layout/manifest.json',

    // Guided-navigation publication (local) — narration synced to text.
    'guided_navigation.webpub': '/test-fixtures/guided-navigation/manifest.json',

    // Nota comic-book media-overlay EPUB (local).
    'comic.webpub': '/test-fixtures/comic/manifest.json',
  };
}
