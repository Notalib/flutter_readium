# flutter_readium_platform_interface

[![pub package](https://img.shields.io/pub/v/flutter_readium_platform_interface.svg)](https://pub.dev/packages/flutter_readium_platform_interface)

The platform interface package for [`flutter_readium`](https://pub.dev/packages/flutter_readium).

This package defines the abstract `FlutterReadiumPlatform` class, all shared Dart models (`Publication`, `Locator`, `EPUBPreferences`, `ReaderDecoration`, …), and the default `MethodChannel` implementation that native plugins wire into.

---

## Usage

**You do not need to depend on this package directly.** Add `flutter_readium` to your `pubspec.yaml` and it will be included transitively.

If you are implementing a new platform plugin for `flutter_readium`, extend `FlutterReadiumPlatform` and call `FlutterReadiumPlatform.instance = MyPlatformImpl()` during plugin registration.

```dart
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';

class MyPlatformImpl extends FlutterReadiumPlatform {
  @override
  Future<Publication> openPublication(String pubUrl) async { ... }
  // implement remaining abstract members
}
```

---

## Models

The key model types exported by this package:

| Type | Description |
|------|-------------|
| `Publication` | Top-level publication container |
| `Locator` | Position identifier within a resource |
| `EPUBPreferences` | EPUB display preferences (font, theme, …) |
| `TTSPreferences` | TTS playback preferences |
| `AudioPreferences` | Audio playback preferences |
| `ReaderDecoration` | Highlight / decoration applied to a range |
| `ReadiumTimebasedState` | Timebased navigator playback state |
| `ReadiumError` | Structured error from native to Dart |

---

## Links

- [flutter_readium on pub.dev](https://pub.dev/packages/flutter_readium)
- [Repository](https://github.com/notalib/flutter_readium)
- [Issue tracker](https://github.com/notalib/flutter_readium/issues)

---

## License

BSD 3-Clause — see [LICENSE](LICENSE).
