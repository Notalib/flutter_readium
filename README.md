# flutter_readium

A Flutter wrapper for the Readium r2-navigator-kotlin and r2-navigator-swift.

This branch contains an "as-is" version of the plugin as used in Nota's LYT4 app, named "Nota Bibliotek 2.0" on app stores.
There are a lot of Nota specific solutions, to things that were later integrated into the readium components.

Nota mainly operates on WebPublications, containing standard EPUBs, with and without text and media overlays.
This plugin also has builtin support for downloading and streaming publications.

## Plans
We will work on the main branch on a modernized version using newest toolkits and attempt to utilize more of the toolkit functionality.

Work TODO:
- [ ] Use Preferences API on both platforms.
- [ ] Use Decorator API for highlighting.
- [ ] Test TTS and Audio navigators for maturity, possibly replacing our own audio handlers.

## Adding flutter_readium to your project

To use, add to `pubspec.yaml`:

```yaml
dependencies:
  flutter_readium: ^x.y.z
```

If using the audio part of the plugin, call `AudioService.init(…)` from `main()`.

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
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
```

#### audio_service

- See https://pub.dev/documentation/audio_service/latest/#android-setup for details.

- If using the `AudioService` for audio, also add the `<service>` and `<receiver>` to the
  `<application>` element (not the `<activity>` element):

```html
<manifest …>
  …
  <application …>
    <activity …>
      …
    </activity>
    <service
      android:name="com.ryanheise.audioservice.AudioService"
      android:exported="true">
      <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
      </intent-filter>
    </service>
    <receiver
      android:name="com.ryanheise.audioservice.MediaButtonReceiver"
      android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
      </intent-filter>
    </receiver>
    …
  </application>
  …
</manifest>
```

- Also, add to your `FlutterFragmentActivity`:
```kotlin
class MainActivity : FlutterFragmentActivity() {
  override fun provideFlutterEngine(context: Context): FlutterEngine? =
    AudioServicePlugin.getFlutterEngine(context)
}
```

#### flutter_downloader

- For flutter_downloader, add any needed translations, see:
  https://github.com/fluttercommunity/flutter_downloader#optional-configuration-1

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

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
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

#### flutter_downloader

- To allow flutter_downloader to work, manually edit your `ios/Runner/AppDelegate.swift`:

```swift
import UIKit
import Flutter
import flutter_downloader

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // *** ADD THIS: ***
    FlutterDownloaderPlugin.setPluginRegistrantCallback(registerPlugins)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// *** AND ADD THIS: ***
private func registerPlugins(registry: FlutterPluginRegistry) {
    if (!registry.hasPlugin("FlutterDownloaderPlugin")) {
       FlutterDownloaderPlugin.register(with: registry.registrar(forPlugin: "FlutterDownloaderPlugin")!)
    }
}
```

## Instructions that don't work after all, but might be used in the future. Please ignore for now.

Since the r2_navigator_swift dependency uses SPM, add it to your project manually:

- Open your `ios/Runner.xcworkspace` with XCode.
- Go to `Runner` on the left (click the folder icon at the top left, if it's not visible).
- Go to `Runner` under `PROJECT` in the other pane.
- Click `Swift Packages` near the middle top.
- Click the `+` icon.
- Add:
  - `https://github.com/readium/r2-navigator-swift.git`
  - `https://github.com/readium/r2-streamer-swift.git`
  - `https://github.com/readium/r2-shared-swift.git`
- If using Flutter ≤ 2.3.0:
  - See [#76868](https://github.com/flutter/flutter/issues/76868).
  - Close `ios/Runner.xcworkspace` and open `ios/Runner.xcodeproj` instead.
  - Go to File/Project settings/Advanced, and change “Legacy” to “Xcode Default”.
  - Close `ios/Runner.xcodeproj` and go back to `ios/Runner.xcworkspace`.
