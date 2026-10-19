import 'dart:async';

import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/readium_integration_harness.dart';

class _AudioPlatform extends FlutterReadiumPlatform {
  final states = StreamController<ReadiumTimebasedState>.broadcast(sync: true);
  Future<void> Function()? onPlay;
  bool paused = false;

  @override
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged => states.stream;

  @override
  Future<void> play(Locator? fromLocator) async => onPlay?.call();

  @override
  Future<void> pause() async {
    paused = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('timedPhase', () {
    test('returns the action result', () async {
      expect(await timedPhase('result', () async => 42), 42);
    });

    test('preserves action failures', () async {
      final error = StateError('enable failed');
      await expectLater(
        timedPhase<void>('enable', () async => throw error),
        throwsA(same(error)),
      );
    });

    test('bounds a hung action and names the failed phase', () async {
      final pending = Completer<void>();
      await expectLater(
        timedPhase('audio enable', () => pending.future, timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TestFailure>().having((error) => error.message, 'message', contains('audio enable'))),
      );
      pending.complete();
    });
  });

  group('expectConditionHolds', () {
    test('observes the full success window', () async {
      final watch = Stopwatch()..start();
      const duration = Duration(milliseconds: 40);
      await expectConditionHolds(() => true, duration: duration, reason: 'Must stay true');
      expect(watch.elapsed, greaterThanOrEqualTo(duration));
    });

    test('fails before the observation window ends on a recorded violation', () async {
      var valid = true;
      final violation = Timer(const Duration(milliseconds: 10), () => valid = false);
      addTearDown(violation.cancel);
      await expectLater(
        expectConditionHolds(
          () => valid,
          duration: const Duration(seconds: 5),
          reason: 'Unexpected retry',
        ).timeout(const Duration(seconds: 2)),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('audio helpers', () {
    late FlutterReadiumPlatform original;
    late _AudioPlatform platform;
    final playing = ReadiumTimebasedState(
      state: TimebasedState.playing,
      currentLocator: Locator(href: 'one.mp3', type: 'audio/mpeg'),
    );

    setUp(() {
      original = FlutterReadiumPlatform.instance;
      platform = _AudioPlatform();
      FlutterReadiumPlatform.instance = platform;
    });

    tearDown(() async {
      FlutterReadiumPlatform.instance = original;
      await platform.states.close();
    });

    test('captures a playing locator emitted during enable and cancels the subscription', () async {
      await exerciseAudioPlayback(
        FlutterReadium(),
        enable: () async => platform.states.add(playing),
      );
      expect(platform.paused, isTrue);
      expect(platform.states.hasListener, isFalse);
    });

    test('captures a locator emitted during play without requiring playing', () async {
      platform.onPlay = () async => platform.states.add(
        ReadiumTimebasedState(state: TimebasedState.paused, currentLocator: playing.currentLocator),
      );
      await expectAudioSessionStarts(FlutterReadium(), enable: () async {});
      expect(platform.paused, isTrue);
      expect(platform.states.hasListener, isFalse);
    });

    test('cancels the subscription when enable throws', () async {
      final error = StateError('enable failed');
      await expectLater(
        exerciseAudioPlayback(FlutterReadium(), enable: () async => throw error),
        throwsA(same(error)),
      );
      expect(platform.states.hasListener, isFalse);
    });

    test('cancels the subscription when play throws', () async {
      platform.onPlay = () async => throw StateError('play failed');
      await expectLater(
        exerciseAudioPlayback(FlutterReadium(), enable: () async {}),
        throwsA(isA<StateError>()),
      );
      expect(platform.states.hasListener, isFalse);
    });

    test('fails and cancels when playing has no locator', () async {
      await expectLater(
        exerciseAudioPlayback(
          FlutterReadium(),
          enable: () async => platform.states.add(const ReadiumTimebasedState(state: TimebasedState.playing)),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TestFailure>()),
      );
      expect(platform.states.hasListener, isFalse);
      expect(platform.paused, isFalse);
    });
  });
}
