import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_readium_platform_interface/method_channel_flutter_readium.dart';
import 'package:flutter_readium_platform_interface/src/index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('onTextLocatorChanged resilience to bad native events', () {
    late MethodChannelFlutterReadium methodChannelReadium;
    final testTextLocator = Locator(
      href: 'chapter1.html',
      type: 'text/xhtml',
      locations: Locations(cssSelector: '#loc1'),
    );

    setUp(() {
      methodChannelReadium = MethodChannelFlutterReadium();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(methodChannelReadium.textLocatorChannel.name),
        (methodCall) async => null,
      );
    });

    /// Pushes a single event through the *real* EventChannel plumbing (the
    /// same path native `sendEvent` calls use), mirroring how the existing
    /// `onTextLocatorChanged emits the locator` test drives the channel.
    Future<void> emit(dynamic value) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          methodChannelReadium.textLocatorChannel.name,
          methodChannelReadium.textLocatorChannel.codec.encodeSuccessEnvelope(value),
          (_) {},
        );

    /// Listens with `cancelOnError: true` — the one subscription style that
    /// actually drops a broadcast stream on the first unhandled error, so a
    /// pass here proves the bad event never reaches the stream as an error.
    Future<void> expectSurvives(dynamic badEvent) async {
      final events = <Locator>[];
      final errors = <Object>[];
      methodChannelReadium.onTextLocatorChanged.listen(
        events.add,
        onError: errors.add,
        cancelOnError: true,
      );

      await emit(badEvent);
      await Future<void>.delayed(Duration.zero);
      await emit(jsonEncode(testTextLocator.toJson()));
      await Future<void>.delayed(Duration.zero);

      expect(errors, isEmpty, reason: 'bad event must be dropped, not surfaced as a stream error');
      expect(events, [testTextLocator], reason: 'the valid event sent after the bad one must still arrive');
    }

    // Native `try? finalLocator.jsonString()` sends nil on serialization failure.
    test('a nil event is dropped and does not kill the stream', () => expectSurvives(null));

    test('malformed JSON is dropped and does not kill the stream', () => expectSurvives('not valid json {'));

    test(
      'a locator JSON missing "type" is dropped and does not kill the stream',
      () => expectSurvives(jsonEncode({'href': 'chapter1.html'})),
    );
  });
}
