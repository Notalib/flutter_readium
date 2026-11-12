**`ReadiumReaderWidget.allowScreenReaderNavigation` exposes e-book text to screen readers.**
The content was always hidden from VoiceOver/TalkBack, so braille displays could not show it. Pass `true` to make it reachable; the default `false` keeps today's behaviour. It is read at view creation, so change the widget `key` to apply a new value.
