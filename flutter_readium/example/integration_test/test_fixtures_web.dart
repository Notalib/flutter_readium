// Web fixture loader — returns URLs to webpub manifests the ts-toolkit
// HttpFetcher can fetch directly.
//
// Most fixtures are served locally from `example/web/` (Flutter copies the
// whole `web/` tree into the build output, so they resolve at the app origin
// during `flutter drive -d chrome`). Keeping them local removes the network
// dependency on external hosts and makes CI deterministic. The packaged Nota
// `.webpub` / `.audiobook` assets were exploded (and trimmed to a few chapters)
// into `example/web/` — see `example/assets/pubs/README.md`.
//
// Moby-Dick stays remote: it is the shared reflowable workhorse for many
// cross-platform tests and ships only as a `.epub` (no RWPM manifest to
// explode), so re-hosting it locally would mean generating a manifest by hand.

Future<Map<String, String>> loadFixturePaths() async {
  return const {
    // Moby-Dick EPUB served as exploded webpub by readium.org (reflowable).
    'moby_dick.epub': 'https://readium.org/webpub-manifest/examples/MobyDick/manifest.json',

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
