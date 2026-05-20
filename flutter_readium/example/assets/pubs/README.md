
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

## Regenerating the PDFs

`time_machine.pdf` and `alice.pdf` are rendered from Project Gutenberg HTML via
headless Chrome:

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
