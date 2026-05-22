# Text-to-Speech

## Enabling TTS

```dart
await reader.ttsEnable(TTSPreferences(speed: 1.0));
await reader.play(null); // start from current position
```

## Playback controls

```dart
await reader.play(null);
await reader.pause();
await reader.resume();
await reader.stop();
await reader.next();      // next utterance
await reader.previous();  // previous utterance
```

## Listing available voices

Combines system voices with Readium's bundled voice-data registry:

```dart
final voices = await reader.ttsGetAvailableVoices();
for (final v in voices) {
  print('${v.name} (${v.language})');
}
```

## Setting a voice

```dart
// Use for all content languages
await reader.ttsSetVoice(voice.identifier, null);

// Use only when the content language matches
await reader.ttsSetVoice(voice.identifier, 'da');
```

## Updating preferences

```dart
await reader.ttsSetPreferences(TTSPreferences(speed: 1.4, pitch: 1.0));
```

## Decoration styles (utterance / word highlighting)

```dart
await reader.setDecorationStyle(
  // Sentence highlight
  ReaderDecorationStyle(style: DecorationStyle.highlight, tint: Colors.yellow),
  // Word underline
  ReaderDecorationStyle(style: DecorationStyle.underline, tint: Colors.orange),
);
```

Pass `null` for either to use the default style.

## State stream

```dart
_sub = reader.onTimebasedPlayerStateChanged.listen((state) {
  if (state.state == TimebasedState.failure) {
    // state.ttsErrorType is non-null here
  }
});
```

## Platform notes

| Platform | Notes |
|----------|-------|
| iOS | AVSpeechSynthesizer; voices depend on downloaded system languages |
| Android | Android TTS engine; additional language packs via system settings |
| Web | Active browser tab required; word-level highlighting is Chrome-only |
