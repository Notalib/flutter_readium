# Plugin: flutter_readium

A Flutter wrapper for the Readium toolkits for ebooks, audiobooks and comics (kotlin-toolkit & swift-toolkit).

This branch is under active development and meant to replace the `nota-lyt4` branch,
which implements both TTS and Text+Audio sync on top of the native toolkits via other Flutter plugins.

This plugin is supposed to support both EPUB and WebPubs, with or without pre-recorded audio.

## Plans
We will work on the main branch on a modernized and simple API using newest toolkits and utilize much more of the toolkit functionality.

See repo Issues for up-to-date progress.

General TODO:
- [X] Use Preferences API on both platforms.
- [X] Use Decorator API for highlighting.
- [X] Test TTS and Audio navigators for maturity, possibly replacing our own audio handlers.
- [ ] Finding: Readium native toolkits do not yet support MediaOverlays, making support for "karaoke books" difficult.
      We either wait for this to be implemented, or do something similar to the `nota-lyt4` branch and use `audio_service` and `just_audio` plugins for MediaOverlay playback.

## Adding flutter_readium to your project

To use, add to `pubspec.yaml`:

```yaml
dependencies:
  flutter_readium: ^x.y.z
```

Also, update your Android and iOS projects as follows:

### Android

- A minSdkVersion ≥ 24 in `android/app/build.gradle` is required.
- If your main activity extends `FlutterActivity`, change it to extend `FlutterFragmentActivity`
  instead. This fixes the `MainActivity cannot be cast to androidx.fragment.app.FragmentActivity`
  error.
- If using the `AudioService` for TTS, add to the `<manifest>` element of
  your `android/app/src/main/AndroidManifest.xml` file:

```html
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

### iOS

- Manually add the `pod` lines to your `ios/Podfile`:

```rb
target 'Runner' do
  use_frameworks!
  use_modular_headers!
  pod 'PromiseKit', '~> 8.1'

  pod 'ReadiumShared', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.2.0/Support/CocoaPods/ReadiumShared.podspec'
  pod 'ReadiumInternal', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.2.0/Support/CocoaPods/ReadiumInternal.podspec'
  pod 'ReadiumStreamer', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.2.0/Support/CocoaPods/ReadiumStreamer.podspec'
  pod 'ReadiumNavigator', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.2.0/Support/CocoaPods/ReadiumNavigator.podspec'
  pod 'ReadiumOPDS', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.2.0/Support/CocoaPods/ReadiumOPDS.podspec'
  pod 'ReadiumAdapterGCDWebServer', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.2.0/Support/CocoaPods/ReadiumAdapterGCDWebServer.podspec'
  pod 'ReadiumZIPFoundation', podspec: 'https://raw.githubusercontent.com/readium/podspecs/refs/heads/main/ReadiumZIPFoundation/3.0.0/ReadiumZIPFoundation.podspec'

  ...
end
```

- To allow the local streamer on 127.0.0.1 to work, manually add to your `ios/Runner/Info.plist`:

```html
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```
