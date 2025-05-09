import 'package:flutter_readium_platform_interface/method_channel_flutter_readium.dart';
import 'package:flutter_readium_platform_interface/src/_index.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('$MethodChannelFlutterReadium', () {
    final log = <MethodCall>[];
    late MethodChannelFlutterReadium methodChannelReadium;
    final testTextLocator = Locator(
      href: 'chapter1.html',
      type: 'text/xhtml',
      locations: Locations(cssSelector: '#loc1'),
      text: LocatorText(before: 'a', highlight: 'b', after: 'c'),
      xNote: 'myNote',
      xType: XType.lastmark,
    );

    setUp(() async {
      methodChannelReadium = MethodChannelFlutterReadium();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannelReadium.methodChannel,
        (methodCall) async {
          log.add(methodCall);
          switch (methodCall.method) {
            case 'openPublication':
              return 'TODO';
            case 'ttsEnable':
              return true;
            case 'goRight':
              return true;
            default:
              return null;
          }
        },
      );
      log.clear();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(methodChannelReadium.locatorChannel.name),
        (methodCall) async {
          switch (methodCall.method) {
            case 'listen':
              await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
                methodChannelReadium.locatorChannel.name,
                methodChannelReadium.locatorChannel.codec.encodeSuccessEnvelope(testTextLocator),
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
      final result = await methodChannelReadium.onTextLocatorChanged.first;
      expect(result, testTextLocator);
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
