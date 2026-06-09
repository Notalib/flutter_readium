---
applyTo: '**'
---

# Context7 MCP — Readium & Flutter Documentation

Use the `context7` MCP server proactively when working with Readium toolkit APIs or Flutter/Dart framework APIs — **without waiting for the user to ask**. Your training data may be stale or miss recent API changes.

## Two-step workflow

1. `resolve-library-id` — map a library name to its Context7 ID.
2. `get-library-docs` — fetch relevant docs for that ID, scoped by a topic query.

## Library IDs (pre-resolved)

| Library | Context7 ID |
|---|---|
| Readium Swift Toolkit | `/readium/swift-toolkit` |
| Readium Kotlin Toolkit | `/readium/kotlin-toolkit` |
| Readium Web (TS) | `/readium/ts-toolkit` |
| Flutter | `/websites/flutter_dev` |
| Flutter API reference | `/websites/api_flutter_dev` |

Use `get-library-docs` with a focused `topic` query, e.g.:
- `"Locator navigation"` for locator / navigator APIs
- `"EPUB decorations"` for highlight/decoration APIs
- `"TTS ReadingProgression"` for TTS APIs
- `"Publication resource loading"` for resource/fetcher APIs
