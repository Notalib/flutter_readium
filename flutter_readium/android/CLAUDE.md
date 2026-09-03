# flutter_readium — Android (Kotlin)

Thin wrapper over [kotlin-toolkit](https://github.com/readium/kotlin-toolkit/); the pinned version is `ext.readium_version` in `build.gradle`. Repo-wide instructions: `../../CLAUDE.md`.

- **Before declaring any Kotlin changes done:** run `./gradlew :flutter_readium:compileDebugKotlin` in `../example/android/` and fix all errors.
- **Kotlin formatting**: after writing or editing any Kotlin file, run `ktlint --format` on it. All violations must be resolved before committing.
- **Log messages**: every `PluginLog.*` call must start with `::functionName` (double colon, then the exact name of the enclosing function). For lambdas, use the enclosing named function. Example: `PluginLog.d(TAG, "::goBackward. Navigator not ready.")`. Single-colon or missing prefixes are bugs; so are wrong function names from copy-paste.
- **Navigator null guard**: every `suspend` function that needs the navigator must capture it as a local with a `?: run { }` early-return guard, then wrap direct navigator calls in `return withContext(coroutineContext) { }`. Functions that only call other wrapper functions (e.g. `evaluateJavascript`) delegate instead — no guard or `withContext` of their own.

  ```kotlin
  val navigator = epubNavigator ?: run {
      PluginLog.w(TAG, "::myFunction. Navigator not ready.")
      return
  }
  return withContext(coroutineContext) { navigator.someCall() }
  ```

## Toolchain

`minSdkVersion 24`, `compileSdk 36`, Kotlin 2.3.21, Java 18 source/target.
The plugin fallback uses AGP 8.13.2; the example validates AGP 9.3.0 with Gradle 9.5.
