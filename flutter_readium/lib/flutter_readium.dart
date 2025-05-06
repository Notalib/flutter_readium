import 'dart:async';

import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_readium_platform_interface/src/reader/reader_widget_interface.dart';
export 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';

class FlutterReadium {
  /// Constructs a singleton instance of [FlutterReadium].
  factory FlutterReadium() {
    _singleton ??= FlutterReadium._();
    return _singleton!;
  }

  FlutterReadium._();

  static FlutterReadium? _singleton;

  static FlutterReadiumPlatform get _platform {
    return FlutterReadiumPlatform.instance;
  }

  Future<Publication> openPublication(String pubUrl) {
    return _platform.openPublication(pubUrl);
  }

  Stream<Locator> get onPageChanged {
    return _platform.onTextLocatorChanged;
  }

  Future<void>? goLeft() {
    return _platform.goLeft();
  }

  Future<void>? goRight() {
    return _platform.goRight();
  }

  Future<void> skipToNext() {
    return _platform.skipToNext();
  }

  Future<void> skipToPrevious() {
    return _platform.skipToPrevious();
  }

  Future<void> setEPUBPreferences(EPUBPreferences preferences) async =>
      await _platform.setEPUBPreferences(preferences);

  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async =>
      await _platform.applyDecorations(id, decorations);
}
