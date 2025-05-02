import 'dart:async';

import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
export 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
// export 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart'
//   show BatteryState;

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

  Future<String> get platformVersion {
    return _platform.platformVersion;
  }

  Future<Publication> openPublication(String pubUrl) {
    return _platform.openPublication(pubUrl);
  }
}
