---
description: Web TypeScript conventions for the flutter_readium plugin.
applyTo: 'flutter_readium/web/**/*.ts'
---

# TypeScript Conventions

## Locator serialization

`@readium/shared` Locators store extra location fields (e.g. `cssSelector`, `tocHref`) in `locations.otherLocations` as a `Map<string, any>`. `JSON.stringify(locator)` **silently drops all Map entries**.

- Always use `JSON.stringify(locator.serialize())` when emitting a Locator to Dart.
- Use `locator.serialize()` when embedding a locator inside a larger object before stringifying.
- For deep-clones: `JSON.parse(JSON.stringify(locator.serialize()))` — not `JSON.parse(JSON.stringify(locator))`.
- Read `otherLocations` via the Map API: `locator.locations?.otherLocations?.get('cssSelector')` — not `(locator.locations as any)?.cssSelector`.

## Built JS

Do **not** hand-edit the compiled JS in `example/web/`. Edit TS sources in `flutter_readium/web/_scripts/`, then run `bin/update_web_example` from the repo root to rebuild and copy the bundle.

## Linting

```bash
cd flutter_readium && npm run lint
```
