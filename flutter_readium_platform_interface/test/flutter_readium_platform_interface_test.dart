import 'package:flutter_readium_platform_interface/src/enums.dart';
import 'package:flutter_readium_platform_interface/method_channel_flutter_readium.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('$MethodChannelFlutterReadium', () {
    final log = <MethodCall>[];
    late MethodChannelFlutterReadium methodChannelReadium;

    setUp(() async {
      methodChannelReadium = MethodChannelFlutterReadium();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannelReadium.methodChannel,
        (MethodCall methodCall) async {
          log.add(methodCall);
          switch (methodCall.method) {
            case 'getBatteryLevel':
              return 100;
            case 'isInBatterySaveMode':
              return true;
            case 'getBatteryState':
              return 'charging';
            default:
              return null;
          }
        },
      );
      log.clear();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(methodChannelReadium.eventChannel.name),
        (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'listen':
              await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                  .handlePlatformMessage(
                methodChannelReadium.eventChannel.name,
                methodChannelReadium.eventChannel.codec.encodeSuccessEnvelope('full'),
                (_) {},
              );
              break;
            case 'cancel':
            default:
              return null;
          }
          return null;
        },
      );
    });

    test('onBatteryChanged', () async {
      final result = await methodChannelReadium.onBatteryStateChanged.first;
      expect(result, BatteryState.full);
    });

    //   test('getBatteryLevel', () async {
    //     final result = await methodChannelBattery.batteryLevel;
    //     expect(result, 100);
    //     expect(
    //       log,
    //       <Matcher>[
    //         isMethodCall(
    //           'getBatteryLevel',
    //           arguments: null,
    //         ),
    //       ],
    //     );
    //   });

    //   test('isInBatterySaveMode', () async {
    //     final result = await methodChannelBattery.isInBatterySaveMode;
    //     expect(result, true);
    //     expect(
    //       log,
    //       <Matcher>[
    //         isMethodCall(
    //           'isInBatterySaveMode',
    //           arguments: null,
    //         ),
    //       ],
    //     );
    //   });

    //   test('getBatteryState', () async {
    //     final result = await methodChannelBattery.batteryState;
    //     expect(result, BatteryState.charging);
    //     expect(
    //       log,
    //       <Matcher>[
    //         isMethodCall(
    //           'getBatteryState',
    //           arguments: null,
    //         ),
    //       ],
    //     );
    //   });
  });
}
