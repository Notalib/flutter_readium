**Web: `ttsEnable` no longer starts reading.**
It now only prepares TTS, as on iOS and Android. Call `play(null)` after it to start, as the TTS guide already shows; apps that did so started TTS twice per press on web.
