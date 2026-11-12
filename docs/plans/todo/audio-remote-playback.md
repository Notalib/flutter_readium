# Audio Remote Playback (AirPlay, Chromecast, Web Remote Playback)

**Type:** Cross-platform feature
**Platforms affected:** iOS, Android, Web
**Estimated effort:** AirPlay S (done) · Web Remote Playback S-M · Android output switcher S-M · Chromecast L per platform

## Context

Listeners want to send audiobook, Media Overlay and TTS playback to an AirPlay speaker, a Chromecast or a smart TV. This plan records what the upstream Readium toolkits support today, what the plugin exposes, and what full support would take. Findings were checked against the toolkit sources on 2026-11-09; re-check the pinned versions (`bin/readium_versions`) before acting on them.

There are two distinct mechanisms, and they have very different costs:

- **Route the audio.** The device decodes the audio and streams the output to the receiver (AirPlay 2 audio, Bluetooth). The app keeps playing as before. Readium's resource pipeline, DRM and TTS keep working.
- **Hand over a URL.** The receiver fetches and plays the media itself (Google Cast, AirPlay "external playback", the web Remote Playback API). It only works when the receiver can fetch every reading-order resource over http(s), with auth carried in the URL.

## Upstream state

| Toolkit | Checked version | Remote playback |
|---|---|---|
| swift-toolkit | 3.11.1<br>(pin 3.11.0) | AirPlay audio routing.<br>No Cast. |
| kotlin-toolkit | 3.4.0 (pin) | None. |
| ts-toolkit navigator | 2.15.0<br>(pin ^2.13.2) | Remote Playback API hooks. |

### iOS (swift-toolkit)

- `AudioNavigator` configures the audio session as `.playback` / `.spokenAudio` / `.longFormAudio` (`Sources/Navigator/Audiobook/AudioNavigator.swift`, `Configuration.init`). `.longFormAudio` is what makes AirPlay 2 routing from Control Center, the lock screen or `AVRoutePickerView` work.
- `makePlayer()` sets `player.allowsExternalPlayback = false`. AVPlayer therefore never hands the URL to the receiver; audio is routed instead. This is required, because audio is fed through `ResourceAssetLoader` (a custom `AVAssetResourceLoader` scheme) that a receiver could not resolve.
- `PublicationSpeechSynthesizer` uses the same session configuration. The upstream changelog lists a fix for AirPlay with the screen locked.
- No Google Cast support, and no issue or PR proposing it.

### Android (kotlin-toolkit)

- No Cast or MediaRouter code anywhere.
- Audio goes through the `AudioEngine` interface (`readium/navigators/media/audio/.../AudioEngine.kt`, `asPlayer(): Player`). The only engine, `ExoPlayerEngine`, reads bytes from publication resources via `ExoPlayerDataSource`.
- The TTS session adapter always reports `DeviceInfo.PLAYBACK_TYPE_LOCAL` (`TtsSessionAdapter.kt`). That is inherent: speech is synthesized on the device.
- Media3 1.9+ rewrote `media3-cast`'s `CastPlayer` to switch between a local ExoPlayer and a Cast session automatically. The plugin uses media3 1.11.1, but Readium constructs its ExoPlayer inside the engine, so using `CastPlayer` means writing a custom `AudioEngine`.
- No issue or PR proposing Cast.

### Web (ts-toolkit `@readium/navigator`)

- `AudioNavigator` (added in readium/ts-toolkit#202) exposes a `remotePlayback` getter on a media element that is never swapped, a `remotePlaybackStateChanged` listener (`connecting` / `connected` / `disconnected`), and `contentProtection.disableRemotePlayback`.
- The receiver fetches the element's `src` itself, so custom request headers (such as auth headers) are not sent. Tracks fed through an `AudioMseLoader` play from a `blob:` URL, which very likely cannot be cast. The plugin passes no `mseLoaderFactory`, so its `src` is the plain http(s) track URL (checked in code, 2026-11-10). The pitch-preserving Web Audio path does not apply on the receiver.
- The navigator has no `prompt()` or `watchAvailability()` wrappers; callers use `remotePlayback` (the element's `remote`) directly. It fires no initial state. The browser never names the device, so web can't tell Cast from AirPlay.
- `HTMLMediaElement.remote` support (MDN): Chrome desktop 121, Chrome Android 56, Safari 13.1. Firefox has none.
- Web TTS (`speechSynthesis`) cannot be cast.

## Plugin state

- **iOS (done):** AirPlay routing works with the default configuration. `BackgroundPlaybackAudioSession` only changes when the session ends. `ReadiumAudioRoutePicker` wraps `AVRoutePickerView`, and `FlutterReadium().onAudioRouteChanged` reports the current output type and name. The example app uses both on the player controls.
- **Web:** `FlutterAudioNavigator.ts` passes a no-op `remotePlaybackStateChanged` listener. Dart has no way to call `prompt()`.
- **Android:** nothing; `onAudioRouteChanged` never emits.

## Remaining work

1. **Web Remote Playback (S-M).** Forward `remotePlaybackStateChanged` to Dart, add a method that calls `navigator.remotePlayback.prompt()` from a user gesture, and show a web `ReadiumAudioRoutePicker` only while `watchAvailability` reports a device. Chrome casts; Safari offers AirPlay. Only works for publications whose audio is served from plain http(s) URLs that the receiver can reach, with CORS headers for Cast. Open: whether `prompt()` counts as a user gesture from a Flutter pointer event, whether a navigator recreate drops the session, whether the plugin should set `disableRemotePlayback` by default, and whether web needs a `remotePlayback` route type since it can't tell Cast from AirPlay.
2. **Android output switcher (S-M).** androidx.mediarouter `SystemOutputSwitcherDialogController.showDialog` opens the system switcher on API 30+ only, so API 24–29 need a fallback or no picker. Report routes with `AudioManager.getDevices` and `AudioDeviceCallback` (API 23, no permission). Whether MediaRouter's selected route reliably marks the active output is unverified. No Cast dependency.
3. **Chromecast on Android (L).** A custom `AudioEngine` on media3 `CastPlayer`, rebuilt into `PluginMediaService`'s media session. `play-services-cast-framework` must be optional (for example a separate `flutter_readium_cast` package), because devices without Google Play Services can't load it. Apps register a receiver app ID (or use the Default Media Receiver) and an `OptionsProvider`. On Android 17, an app sees Cast routes in `MediaRouter` / `MediaRouter2` only after declaring and being granted `ACCESS_LOCAL_NETWORK`, although the system switcher shows them regardless. A probe on a Galaxy S23 then cast an MP3 to a Nest speaker; an MP4 load buffered and reset for unknown reasons, and the session took about 19 s to start.
4. **Chromecast on iOS (L).** The Google Cast iOS SDK plus a second player next to Readium's AVPlayer-based navigator. Apps add `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_googlecast._tcp`).

Chromecast also affects synced narration: highlighting would be driven by position updates from the receiver, which arrive late.

## Open decisions before Chromecast

- **Content reachability.** Which publications can be served to a receiver at all? Local files, LCP-protected publications and anything the Readium toolkits read through their own resource layer would need an on-device HTTP server exposing decrypted content on the local network.
- **Rights.** Sending protected or rights-restricted material to third-party devices is a decision for each app and its content providers. The plugin should let apps turn remote playback off, not decide for them.
- **Upstream.** Raise Cast with Readium before building it, so the Kotlin `AudioEngine` work can live upstream instead of only in this plugin.
