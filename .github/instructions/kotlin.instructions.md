---
description: Android/Kotlin conventions for the flutter_readium plugin.
applyTo: 'flutter_readium/android/**/*.kt'
---

# Kotlin Conventions

## Formatting

After writing or editing any Kotlin file, run `ktlint --format` on it (or `./gradlew ktlintFormat` from `flutter_readium/android/`). The `standard:package-name` violation for `dk.nota.flutter_readium` is pre-existing and cannot be auto-corrected — ignore it. Fix all other violations.

## Log messages

Every `PluginLog.*` call must start with `::functionName` — double colon followed by the exact name of the enclosing function. For lambdas, use the name of the enclosing named function.

```kotlin
PluginLog.d(TAG, "::goBackward. Some detail.")
PluginLog.w(TAG, "::onLocatorChanged. Navigator not ready.")
```

Single-colon prefixes, missing prefixes, and copy-pasted wrong function names are all bugs.

## Navigator null guard

Every `suspend` function that needs the navigator must:
1. Capture it as a local variable with a `?: run { }` early-return guard.
2. Wrap direct navigator calls in `return withContext(coroutineContext) { }`.

```kotlin
val navigator = epubNavigator ?: run {
    PluginLog.w(TAG, "::myFunction. Navigator not ready.")
    return
}
return withContext(coroutineContext) { navigator.someCall() }
```

Functions that only delegate to other wrapper functions (e.g. `evaluateJavascript`) do **not** need their own guard or `withContext`.

## Method channel serialization

Pass Readium-owned objects (`Locator`, `Decoration`, etc.) across the method channel as **JSON strings**. Use plain Maps only for flat plugin-owned structures with a shape fully controlled by this plugin.
