# FlutterReadium class

`FlutterReadium` is a singleton that provides the full reader API. Obtain the instance with `FlutterReadium()`.

## Publication lifecycle

| Method | Description |
|--------|-------------|
| `loadPublication(url)` | Parse a publication manifest without opening it for reading |
| `openPublication(url)` | Open a publication for reading; required before showing [ReadiumReaderWidget] or using any navigation API. :warning: Only one publication can be open at a time. |
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
| `toPhysicalPageIndex(index, pub)` | Navigate to a printed page number. TODO: will be deprecated in favor of `goByLink` |
| `skipToNextTOC(publication, currentTocHref)` | Skip to next chapter |
| `skipToPreviousTOC(publication, currentTocHref)` | Skip to previous chapter |

## Preferences

| Method | Description |
|--------|-------------|
| `setDefaultPreferences(prefs)` | Set EPUB defaults applied to all future publications. See [preferences.md](./preferences.md#preferences) |
| `setEPUBPreferences(prefs)` | Apply EPUB display preferences to the current publication. See [preferences.md](./preferences.md#preferences) |
| `setCustomHeaders(headers)` | Set HTTP headers used for all network requests |
| `setLogLevel(level)` | Set the plugin's internal log verbosity |
| `setAudioRecoveryPolicy(policy)` | Configure audio-stream error recovery (retry attempts, backoff, stall timeout). See [error-codes.md](./error-codes.md#audiorecoverypolicy) |

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
| `ttsEnable(prefs)` | Enable TTS for the current publication. See [preferences.md](./preferences.md#ttspreferences) |
| `ttsSetPreferences(prefs)` | Update TTS preferences without restarting. See [preferences.md](./preferences.md#ttspreferences) |
| `ttsGetAvailableVoices()` | List all available voices |
| `ttsSetVoice(id, language)` | Set a specific voice; `language` scopes it to a content language |
| `setDecorationStyle(utterance, range)` | Set decoration styles for TTS highlighting |

### TODO: Slightly inconsistent that audioEnable takes a fromLocator and ttsEnable doesn't.

## Audio

| Method | Description |
|--------|-------------|
| `audioEnable(prefs, fromLocator)` | Enable audio playback. See [preferences.md](./preferences.md#audiopreferences) |
| `audioSetPreferences(prefs)` | Update audio preferences. See [preferences.md](./preferences.md#audiopreferences) |
| `audioSeekBy(offset)` | Seek by a Duration offset rounded to whole seconds (positive = forwards, negative = backwards) |

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
| `onReaderStatusChanged` | `ReadiumReaderStatus` | Loading, ready, closed, error. See [enums.dart](../../flutter_readium_platform_interface/lib/src/enums.dart) |
| `onTextLocatorChanged` | `Locator` | Visual reader position changes. See [locator.md](./locator.md) |
| `onTimebasedPlayerStateChanged` | `ReadiumTimebasedState` | Audio/TTS playback state. See [timebased_state.dart](../../flutter_readium_platform_interface/lib/src/timebased_state.dart) |
| `onExternalPlaybackCommand` | `ReadiumExternalPlaybackCommand` | System media-control commands such as headphones / Control Center play and pause. See [external_playback_command.dart](../../flutter_readium_platform_interface/lib/src/external_playback_command.dart) |
| `onErrorEvent` | `ReadiumError` | Non-fatal errors. See [readium_exceptions.dart](../../flutter_readium_platform_interface/lib/src/exceptions/readium_exceptions.dart) |
