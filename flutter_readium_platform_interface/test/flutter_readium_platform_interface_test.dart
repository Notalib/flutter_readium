import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_readium_platform_interface/method_channel_flutter_readium.dart';
import 'package:flutter_readium_platform_interface/src/index.dart';
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
    );

    setUp(() async {
      methodChannelReadium = MethodChannelFlutterReadium();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannelReadium.methodChannel, (
            methodCall,
          ) async {
            log.add(methodCall);
            switch (methodCall.method) {
              case 'openPublication':
                return 'TODO';
              case 'ttsEnable':
                return true;
              case 'goForward':
                return true;
              default:
                return null;
            }
          });
      log.clear();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel(methodChannelReadium.textLocatorChannel.name),
            (methodCall) async {
              switch (methodCall.method) {
                case 'listen':
                  await TestDefaultBinaryMessengerBinding
                      .instance
                      .defaultBinaryMessenger
                      .handlePlatformMessage(
                        methodChannelReadium.textLocatorChannel.name,
                        methodChannelReadium.textLocatorChannel.codec
                            .encodeSuccessEnvelope(
                              jsonEncode(testTextLocator.toJson()),
                            ),
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

    test(
      'onTextLocatorChanged emits the locator sent from the platform',
      () async {
        final result = await methodChannelReadium.onTextLocatorChanged.first;
        expect(result, testTextLocator);
      },
    );
  });
}
