
# Test publications

These test publications should be in the public domain or otherwise free of copyright.
Some ones prefixed with a number are self-produced by Nota.

## Publications

| File                      | Media-type        | Contents                      |
| ------------------------- | ----------------- | ----------------------------- |
| moby_dick.epub            | epub              | Ebook                         |
| 712199_ebook.epub         | epub              | Ebook                         |
| 712199_ebook.webpub       | webpub/ebook      | Ebook                         |
| 41654_overlay.epub        | epub              | Ebook /w MediaOverlays        |
| 38533_overlay.webpub      | webpub/ebook      | Ebook /w MediaOverlays        |
| 38533.audiobook           | webpub/audiobook  | Readium Audiobook             |
| flatland_remote.audiobook | webpub/audiobook  | Readium Audiobook (remote)    |
| pdf_test.pdf              | pdf               | PDF (minimal dummy)           |
| time_machine.pdf          | pdf               | PDF (public domain)           |
| alice.pdf                 | pdf               | PDF /w images (public domain) |
| sample_comic.cbz          | cbz               | Comic (synthetic, 3 pages)    |
| 50272-nota-comics.webpub  | webpub/ebook      | Narrated comic (EPUB+MO)      |
| 50272-nota-comics.divina  | divina            | Narrated comic (Guided Nav)   |

## Regenerating the DiViNa comic

`50272-nota-comics.divina` is generated from the EPUB+MediaOverlay comic
`50272-nota-comics.webpub` by `bin/make_comic_divina.py` (repo root). It is the same
content re-expressed in the native Readium DiViNa + Guided Navigation form: the reading
order becomes the page images, and a single `guided-navigation.json` carries each narrated
segment's `audioref` (mp3 time range), `textref` (the page image), and `imgref` (the panel
`#xywh=` region, kept for future panel-zoom). Regenerate with:

```sh
bin/make_comic_divina.py \
  flutter_readium/example/assets/pubs/50272-nota-comics.webpub \
  flutter_readium/example/assets/pubs/50272-nota-comics.divina
```

## Regenerating the PDFs

`time_machine.pdf` and `alice.pdf` are rendered from Project Gutenberg HTML via
headless Chrome (on MacOS in this example):

```sh
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$chrome" --headless=new --disable-gpu --no-pdf-header-footer \
  --print-to-pdf=time_machine.pdf \
  "https://www.gutenberg.org/cache/epub/35/pg35-images.html"
"$chrome" --headless=new --disable-gpu --no-pdf-header-footer \
  --print-to-pdf=alice.pdf \
  "https://www.gutenberg.org/cache/epub/11/pg11-images.html"
```

Gutenberg no longer offers PDF as a native download format, hence the HTML →
Chrome round-trip. The result is a real text-based PDF (selectable text,
embedded fonts) suitable for exercising `PDFPositionsService` and the PDFium
adapter.

## Web integration-test fixtures (`example/web/`)

The web integration tests fetch RWPM `manifest.json` endpoints. To keep CI
deterministic (no dependency on external hosts), most fixtures are served
**locally** from `example/web/` — Flutter copies the whole `web/` tree into the
build output, so each resolves at the app origin during `flutter drive -d chrome`.
The mapping lives in `integration_test/test_fixtures_web.dart`.

| Served path                     | Reading mode        | Produced from                                  |
| ------------------------------- | ------------------- | ---------------------------------------------- |
| `/test-overlay/`                | media overlay       | `38533_overlay_preview.webpub`, trimmed to 4 ch |
| `/test-audiobook-nota/`         | audiobook           | `38533.audiobook`, trimmed to 3 tracks          |
| `/test-guided-navigation/`      | guided navigation   | 38533 guided-nav preview (4 ch)                 |
| `/test-comic/`                  | comic media overlay | `50272-nota-comics.webpub`, exploded as-is      |
| `/test-fixed-layout/`           | fixed-layout EPUB   | hand-authored (inline SVG, public-domain)       |

Reflowable EPUB stays remote (`readium.org` Moby-Dick) — it is the shared
cross-platform workhorse and ships only as `.epub` (no manifest to explode).

The packaged Nota `.webpub` / `.audiobook` assets already contain a relative-href
`manifest.json`, so they were exploded into `example/web/` and trimmed to a few
chapters (drop trailing reading-order entries + the resources/toc/audio they
reference, then recompute `metadata.duration`) to keep them ~3–5 MB each. The
explode/trim is reproducible via `bin/trim_web_fixture.py` — e.g.
`bin/trim_web_fixture.py …/38533_overlay_preview.webpub …/web/test-overlay 4`
(omit the count to explode as-is, as for `test-comic/`).
`test-fixed-layout/` was authored by hand: a `manifest.json` declaring
`metadata.presentation.layout: "fixed"` plus three viewport-sized XHTML pages, each
an inline `<svg>` (no binary images), so the fixture is tiny and unambiguously
public-domain.
