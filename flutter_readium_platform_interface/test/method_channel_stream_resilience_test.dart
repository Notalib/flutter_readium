import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_readium_platform_interface/method_channel_flutter_readium.dart';
import 'package:flutter_readium_platform_interface/src/index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelFlutterReadium methodChannelReadium;
  final subscriptions = <StreamSubscription<dynamic>>[];

  setUp(() {
    methodChannelReadium = MethodChannelFlutterReadium();
  });

  tearDown(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
  });

  /// Pushes a single event through the *real* EventChannel plumbing (the same
  /// path native `sendEvent` calls use), mirroring how the existing
  /// `onTextLocatorChanged emits the locator` test drives the channel.
  Future<void> emit(final EventChannel channel, final dynamic value) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeSuccessEnvelope(value),
        (_) {},
      );

  /// Sends [badEvent], then a known-good event, and asserts the bad one was
  /// dropped without surfacing as a stream error while the good one still
  /// arrived. Uses an ordinary listener with `onError`, which is how consumers
  /// actually subscribe.
  Future<List<T>> expectDroppedNotRaised<T>({
    required final Stream<T> stream,
    required final EventChannel channel,
    required final dynamic badEvent,
    required final dynamic goodEvent,
  }) async {
    final events = <T>[];
    final errors = <Object>[];
    subscriptions.add(stream.listen(events.add, onError: errors.add));

    await emit(channel, badEvent);
    await Future<void>.delayed(Duration.zero);
    await emit(channel, goodEvent);
    await Future<void>.delayed(Duration.zero);

    expect(errors, isEmpty, reason: 'the bad event must be dropped, not surfaced as a stream error');
    expect(events, hasLength(1), reason: 'the valid event sent after the bad one must still arrive');
    return events;
  }

  group('onTextLocatorChanged resilience to bad native events', () {
    final testLocator = Locator(
      href: 'chapter1.html',
      type: 'text/xhtml',
      locations: Locations(cssSelector: '#loc1'),
    );

    Future<void> expectSurvives(final dynamic badEvent) async {
      final events = await expectDroppedNotRaised(
        stream: methodChannelReadium.onTextLocatorChanged,
        channel: methodChannelReadium.textLocatorChannel,
        badEvent: badEvent,
        goodEvent: jsonEncode(testLocator.toJson()),
      );
      expect(events.single.href, testLocator.href);
      expect(events.single.type, testLocator.type);
    }

    // Native `try? finalLocator.jsonString()` sends nil on serialization failure.
    test('a nil event is dropped', () => expectSurvives(null));

    test('malformed JSON is dropped', () => expectSurvives('not valid json {'));

    test('a top-level JSON array is dropped', () => expectSurvives('[1,2,3]'));

    test(
      'a locator JSON missing "type" is dropped',
      () => expectSurvives(jsonEncode({'href': 'chapter1.html'})),
    );
  });

  group('onTimebasedPlayerStateChanged resilience to bad native events', () {
    final testState = ReadiumTimebasedState(
      state: TimebasedState.playing,
      currentOffset: const Duration(seconds: 12),
      currentLocator: Locator(
        href: 'track1.mp3',
        type: 'audio/mpeg',
        locations: Locations(position: 1, progression: 0.5, totalProgression: 0.25),
      ),
    );

    Future<void> expectSurvives(final dynamic badEvent) async {
      final events = await expectDroppedNotRaised(
        stream: methodChannelReadium.onTimebasedPlayerStateChanged,
        channel: methodChannelReadium.timebasedStateChannel,
        badEvent: badEvent,
        goodEvent: jsonEncode(testState.toJson()),
      );
      expect(events.single.state, testState.state);
      expect(events.single.currentLocator?.href, testState.currentLocator?.href);
    }

    // Native `ReadiumTimebasedState.toJsonString()` returns nil on failure.
    test('a nil event is dropped', () => expectSurvives(null));

    test('malformed JSON is dropped', () => expectSurvives('not valid json {'));

    test('a top-level JSON array is dropped', () => expectSurvives('[1,2,3]'));
  });

  group('fromJsonString rejects wrong-shaped JSON instead of throwing', () {
    // Regression: these decoded straight into Map<String, dynamic>, so a
    // top-level array threw a TypeError that `on Exception` could not catch.
    test('Locator', () {
      expect(Locator.fromJsonString('[1,2,3]'), isNull);
      expect(Locator.fromJsonString('"just a string"'), isNull);
    });

    test('ReadiumTimebasedState', () {
      expect(ReadiumTimebasedState.fromJsonString('[1,2,3]'), isNull);
    });

    test('TextSearchResult', () {
      expect(TextSearchResult.fromJsonString('[1,2,3]'), isNull);
    });
  });
}
