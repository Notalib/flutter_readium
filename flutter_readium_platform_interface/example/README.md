# flutter_readium_platform_interface example

This package is the platform interface for [`flutter_readium`](https://pub.dev/packages/flutter_readium). End users should depend on `flutter_readium` directly — the snippets here are for plugin authors who want to add a new platform implementation, or for code that consumes the shared models / streams.

## Implementing a new platform

A platform implementation should extend `FlutterReadiumPlatform` and register itself as the active instance during plugin initialisation.

```dart
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';

class FlutterReadiumExample extends FlutterReadiumPlatform {
  @override
  Future<Publication> openPublication(String pubUrl) async {
    // Delegate to a native channel, an HTTP fetch, an in-memory mock, …
    return Publication(
      links: const [],
      metadata: Metadata(
        localizedTitle: LocalizedString.fromStrings({'en': 'Example Publication'}),
      ),
      readingOrder: const [],
    );
  }

  @override
  Future<void> closePublication() async {}

  // Override the remaining members of FlutterReadiumPlatform as required.
}

void registerExample() {
  FlutterReadiumPlatform.instance = FlutterReadiumExample();
}
```

## Working with the shared models

All models expose hand-written `toJson` / `fromJson` so they can be sent across a method channel or persisted without code generation.

```dart
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';

final locator = Locator(
  href: '/chapter-1.xhtml',
  type: 'application/xhtml+xml',
  locations: Locations(progression: 0.42, totalProgression: 0.17),
);

final encoded = locator.toJson();
final decoded = Locator.fromJson(encoded);

assert(decoded.href == locator.href);
```

See the [project repository](https://github.com/notalib/flutter_readium) for the full reader API, an end-to-end example app, and documentation.