// Web fixture loader — returns URLs to publicly-hosted webpub manifests.
//
// These must be RWPM manifest.json endpoints that the ts-toolkit HttpFetcher
// can fetch directly. Resources (XHTML chapters, audio files) are resolved
// relative to the manifest URL by the Readium navigator.

Future<Map<String, String>> loadFixturePaths() async {
  return const {
    // Moby-Dick EPUB served as exploded webpub by readium.org
    'moby_dick.epub': 'https://readium.org/webpub-manifest/examples/MobyDick/manifest.json',

    // WebPub with media overlays (Nota free publication)
    '38533_overlay_preview.webpub':
        'https://merkur.nota.dk/opds2/publication/free/merkur:libraryid:INSL20260002/stream/WebPubAudio/manifest.json',

    // Audiobook (Nota free publication)
    '38533.audiobook':
        'https://merkur.nota.dk/opds2/publication/free/merkur:libraryid:50791/stream/WebPubAudioOnly/manifest.json',
  };
}
