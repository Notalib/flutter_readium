# FlutterReadium class

`FlutterReadium` is a singleton that provides the full reader API. Obtain the instance with `FlutterReadium()`.

## Publication lifecycle

| Method | Description |
|--------|-------------|
| `loadPublication(url)` | Parse a publication manifest without opening it for reading |
| `openPublication(url)` | Open a publication for reading; required before any navigation |
| `closePublication()` | Close the current publication and release native resources |

```dart
final pub = await FlutterReadium().openPublication(url);
// ...
await FlutterReadium().closePublication();
```

## Navigation

| Method | Description |
|--------|-------------|
| `goForward()` | Next page or section |
| `goBackward()` | Previous page or section |
| `goToLocator(locator)` | Navigate to an exact position; returns `true` on success |
| `goToProgression(value)` | Navigate to a 0.0–1.0 position in the current resource |
| `goByLink(link, pub)` | Navigate to a publication link |
| `toPhysicalPageIndex(index, pub)` | Navigate to a printed page number |
| `skipToNextTOC(publication, currentTocHref)` | Skip to next chapter |
| `skipToPreviousTOC(publication, currentTocHref)` | Skip to previous chapter |

## Preferences

| Method | Description |
|--------|-------------|
| `setDefaultPreferences(prefs)` | Set EPUB defaults applied to all future publications |
| `setEPUBPreferences(prefs)` | Apply EPUB display preferences to the current publication |
| `setCustomHeaders(headers)` | Set HTTP headers used for all network requests |
| `setLogLevel(level)` | Set the plugin's internal log verbosity |

## Decorations

```dart
// Apply (or replace) a named group
await FlutterReadium().applyDecorations('highlights', decorations);

// Clear a group
await FlutterReadium().applyDecorations('highlights', []);
```

## TTS

| Method | Description |
|--------|-------------|
| `ttsEnable(prefs)` | Enable TTS for the current publication |
| `ttsSetPreferences(prefs)` | Update TTS preferences without restarting |
| `ttsGetAvailableVoices()` | List all available voices |
| `ttsSetVoice(id, language)` | Set a specific voice; `language` scopes it to a content language |
| `setDecorationStyle(utterance, range)` | Set decoration styles for TTS highlighting |

## Audio

| Method | Description |
|--------|-------------|
| `audioEnable(prefs, fromLocator)` | Enable audio playback |
| `audioSetPreferences(prefs)` | Update audio preferences |
| `audioSeekBy(offset)` | Seek by a Duration offset (positive = forward) |

## Shared playback controls

Used by both TTS and audio modes:

```dart
await reader.play(locator);   // null = current position
await reader.pause();
await reader.resume();
await reader.stop();
await reader.next();
await reader.previous();
```

## Search

```dart
final results = await FlutterReadium().searchInPublication('query');
```

## Event streams

| Stream | Type | Description |
|--------|------|-------------|
| `onReaderStatusChanged` | `ReadiumReaderStatus` | Loading, ready, closed, error |
| `onTextLocatorChanged` | `Locator` | Visual reader position changes |
| `onTimebasedPlayerStateChanged` | `ReadiumTimebasedState` | Audio/TTS playback state |
| `onErrorEvent` | `ReadiumError` | Non-fatal errors |
