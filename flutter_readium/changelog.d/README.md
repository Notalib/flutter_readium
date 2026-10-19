# Changelog fragments

Do not edit `../CHANGELOG.md` directly. Add one file here per consumer-visible change. `bin/release_prep` compiles the files into `CHANGELOG.md` and deletes them.

File name: `<issue>.<type>.md` (for example `123.fixed.md`, which links issue #123) or `+<slug>.<type>.md` (for example `+web-tts-stall.fixed.md`, no link).

Types: `breaking`, `added`, `changed`, `deprecated`, `removed`, `fixed`, `security`.

Content: a bold one-line lead, then 2–4 lines. Do not start with `- `; the bullet is added for you. Check with `bin/changelog check`.

A change to both packages needs one file here and one in `flutter_readium_platform_interface/changelog.d/`. Full guide: [CONTRIBUTING.md](../../CONTRIBUTING.md#changelog).
