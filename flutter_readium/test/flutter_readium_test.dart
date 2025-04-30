import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_readium_platform_interface/method_channel_flutter_readium.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterReadiumPlatform with MockPlatformInterfaceMixin implements FlutterReadiumPlatform {
  @override
  Future<int> get batteryLevel => Future.value(42);

  @override
  Future<BatteryState> get batteryState => Future.value(BatteryState.full);

  @override
  Future<bool> get isInBatterySaveMode => Future.value(false);

  @override
  Stream<BatteryState> get onBatteryStateChanged => Stream.fromIterable([
        BatteryState.unknown,
        BatteryState.charging,
        BatteryState.full,
        BatteryState.discharging,
      ]);

  @override
  Future<Publication> openPublication(String pubUrl) {
    // TODO: mock openPublication
    throw UnimplementedError();
  }

  @override
  Future<String> get platformVersion => Future.value('42');
}

void main() {
  late FlutterReadium flutterReadium;
  late MockFlutterReadiumPlatform fakePlatform;

  setUpAll(() {
    fakePlatform = MockFlutterReadiumPlatform();
    FlutterReadiumPlatform.instance = fakePlatform;
    flutterReadium = FlutterReadium();
  });

  // test('batteryLevel', () async {
  //   expect(await flutterReadium.batteryLevel, 42);
  // });

  // test('isInBatterySaveMode', () async {
  //   expect(await flutterReadium.isInBatterySaveMode, true);
  // });

  // test('current state of the battery', () async {
  //   expect(await flutterReadium.batteryState, BatteryState.charging);
  // });

  // test('receiving events of the battery state', () async {
  //   final queue = StreamQueue<BatteryState>(battery.onBatteryStateChanged);

  //   expect(await queue.next, BatteryState.unknown);
  //   expect(await queue.next, BatteryState.charging);
  //   expect(await queue.next, BatteryState.full);
  //   expect(await queue.next, BatteryState.discharging);

  //   expect(await queue.hasNext, false);
  // });
}
