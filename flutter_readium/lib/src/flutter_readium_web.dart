import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart';

/// The web implementation of the FlutterReadiumPlatform of the FlutterReadium plugin.
class FlutterReadiumWebPlugin extends FlutterReadiumPlatform {
  FlutterReadiumWebPlugin();

  /// Return [BatteryManager] if the BatteryManager API is supported by the User Agent.
  Future<BatteryManager?> _getBatteryManager() async {
    try {
      return await window.navigator.getBattery().toDart;
    } on NoSuchMethodError catch (_) {
      // BatteryManager API is not supported this User Agent.
      return null;
    } on Object catch (_) {
      // Unexpected exception occurred.
      return null;
    }
  }

  /// Factory method that initializes the FlutterReadium plugin platform with an instance
  /// of the plugin for the web.
  static void registerWith(Registrar registrar) {
    FlutterReadiumPlatform.instance = FlutterReadiumWebPlugin();
  }

  @override
  Future<Publication> openPublication(String pubUrl) {
    // TODO: Use ts-toolkit to open publication.
    throw Error();
  }
}
