import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import 'flutter_readium_platform_interface.dart';
import 'src/utils.dart';

/// An implementation of [BatteryPlatform] that uses method channels.
class MethodChannelFlutterReadium extends FlutterReadiumPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  MethodChannel methodChannel = const MethodChannel('dk.nota.flutter_readium/main');

  /// The event channel used to receive BatteryState changes from the native platform.
  @visibleForTesting
  EventChannel eventChannel = const EventChannel('dk.nota.flutter_readium/events');

  Stream<BatteryState>? _onBatteryStateChanged;

  /// Fires whenever the battery state changes.
  // @override
  Stream<BatteryState> get onBatteryStateChanged {
    _onBatteryStateChanged ??=
        eventChannel.receiveBroadcastStream().map((dynamic event) => parseBatteryState(event));
    return _onBatteryStateChanged!;
  }

  @override
  Future<String> get platformVersion {
    return Future.value("42");
  }

  @override
  Future<Publication> openPublication(String pubUrl) async {
    String publicationString = await methodChannel
        .invokeMethod<String>('openPublication', [pubUrl]).then<String>((dynamic result) => result);
    return Publication.fromJson(json.decode(publicationString) as Map<String, dynamic>);
  }
}
