import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import '../readium_integration_harness.dart';
import '../test_suite_setup.dart';
import '../test_fixtures.dart';

void main() {
  final harness = suiteHarness();

  group('Timebased playback', () {
    test(
      'EPUB TTS reaches playing with a current locator',
      skip: kIsWeb ? 'Web Speech API unavailable in the web test harness' : false,
      () async {
        final path = harness.fixturePath(
          FixtureKeys.reflowableEpub,
          reason: 'Fixture ${FixtureKeys.reflowableEpub} missing from asset bundle',
        );

        await harness.readium.openPublication(path);

        await exerciseAudioPlayback(
          harness.readium,
          enable: () => harness.readium.ttsEnable(TTSPreferences(speed: 1.0)),
          timeout: const Duration(seconds: 60),
        );
      },
    );

    test('media-overlay WebPub opens and plays audio on native', () async {
      final path = harness.fixturePath(
        FixtureKeys.overlayWebpub,
        reason: 'Fixture ${FixtureKeys.overlayWebpub} missing from asset bundle',
      );

      final pub = await harness.readium.openPublication(path);

      expect(pub.readingOrder, isNotEmpty);
      expect(pub.containsMediaOverlays, isTrue, reason: 'Overlay webpub should report media overlays');

      if (!kIsWeb) {
        await exerciseAudioPlayback(
          harness.readium,
          enable: () => harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0)),
        );
      }
    });

    test('audiobook opens and plays audio on native', () async {
      final path = harness.fixturePath(
        FixtureKeys.audiobook,
        reason: 'Fixture ${FixtureKeys.audiobook} missing from asset bundle',
      );

      final pub = await harness.readium.openPublication(path);

      expect(pub.readingOrder, isNotEmpty);
      expect(
        pub.conformsToReadiumAudiobook,
        isTrue,
        reason: 'Audiobook fixture should conform to the Readium audiobook profile',
      );

      if (!kIsWeb) {
        await exerciseAudioPlayback(
          harness.readium,
          enable: () => harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0)),
        );
      }
    });

    group(
      'native audio controls',
      skip: kIsWeb ? 'Real audio playback is not available in the web test harness' : null,
      () {
        test('audiobook pause then resume cycles through state transitions', () async {
          final path = harness.fixturePath(
            FixtureKeys.audiobook,
            reason: 'Fixture ${FixtureKeys.audiobook} missing from asset bundle',
          );

          await harness.readium.openPublication(path);

          final states = <ReadiumTimebasedState>[];
          final sub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
          addTearDown(sub.cancel);

          await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0));
          await harness.readium.play(null);

          await waitUntil(
            () => states.any((s) => s.state == TimebasedState.playing),
            timeout: const Duration(seconds: 10),
            reason: 'Never reached initial playing state',
          );

          await harness.readium.pause();
          await waitUntil(
            () => states.last.state == TimebasedState.paused,
            timeout: const Duration(seconds: 10),
            reason: 'pause() did not produce a paused state',
          );

          await harness.readium.resume();
          await waitUntil(
            () => states.last.state == TimebasedState.playing,
            timeout: const Duration(seconds: 10),
            reason: 'resume() did not return to playing state',
          );

          await harness.readium.pause();
        });

        test('audioSeekBy advances the timebased position', () async {
          final path = harness.fixturePath(
            FixtureKeys.audiobook,
            reason: 'Fixture ${FixtureKeys.audiobook} missing from asset bundle',
          );

          await harness.readium.openPublication(path);

          final states = <ReadiumTimebasedState>[];
          final sub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
          addTearDown(sub.cancel);

          await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0));
          await harness.readium.play(null);

          await waitUntil(
            () => states.any((s) => s.state == TimebasedState.playing && s.currentOffset != null),
            timeout: const Duration(seconds: 20),
            reason: 'Never reached playing state with an offset',
          );

          final beforeSeek = states.last.currentOffset!;
          final seekDuration = const Duration(seconds: 5);
          final tolerance = const Duration(milliseconds: 500);
          final expectedMinOffset = beforeSeek + seekDuration - tolerance;

          await harness.readium.audioSeekBy(seekDuration);
          await harness.readium.resume();

          await waitUntil(
            () => states.last.currentOffset != null && states.last.currentOffset! >= expectedMinOffset,
            timeout: const Duration(seconds: 10),
            reason: 'currentOffset did not advance after audioSeekBy($seekDuration)',
          );

          expect(
            states.last.currentOffset! - beforeSeek,
            greaterThanOrEqualTo(seekDuration - tolerance),
            reason: 'audioSeekBy() should have advanced offset by ~seekDuration',
          );
        });

        test('changing audiobook tracks does not trigger false stall recovery', () async {
          await harness.readium.setAudioRecoveryPolicy(
            const AudioRecoveryPolicy(stallTimeoutSeconds: 3.0),
          );
          addTearDown(
            () => harness.readium.setAudioRecoveryPolicy(const AudioRecoveryPolicy()),
          );

          final path = harness.fixturePath(
            FixtureKeys.audiobook,
            reason: 'Fixture ${FixtureKeys.audiobook} missing from asset bundle',
          );
          final pub = await harness.readium.openPublication(path);
          expect(pub.readingOrder.length, greaterThanOrEqualTo(2));

          final states = <ReadiumTimebasedState>[];
          final errors = <ReadiumError>[];
          final stateSub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
          final errorSub = harness.readium.onErrorEvent.listen(errors.add);
          addTearDown(stateSub.cancel);
          addTearDown(errorSub.cancel);

          await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0));

          final firstLink = pub.readingOrder.first;
          final startedLate = await harness.readium.goToLocator(
            Locator(
              href: firstLink.href,
              type: firstLink.type ?? 'audio/mpeg',
              locations: const Locations(position: 1, fragments: ['t=7']),
            ),
          );
          expect(startedLate, isTrue);
          await harness.readium.play(null);
          await waitUntil(
            () => states.any(
              (state) =>
                  state.state == TimebasedState.playing &&
                  state.currentLocator?.href == firstLink.href &&
                  state.currentOffset != null &&
                  state.currentOffset! >= const Duration(milliseconds: 8500),
            ),
            timeout: const Duration(seconds: 10),
            reason: 'First track never played from the late offset',
          );

          final secondLink = pub.readingOrder[1];
          final changedTrack = await harness.readium.goToLocator(
            Locator(
              href: secondLink.href,
              type: secondLink.type ?? 'audio/mpeg',
              locations: const Locations(position: 2, fragments: ['t=0']),
            ),
          );
          expect(changedTrack, isTrue);

          await waitUntil(
            () => states.any(
              (state) =>
                  state.state == TimebasedState.playing &&
                  state.currentLocator?.href == secondLink.href &&
                  state.currentOffset != null &&
                  state.currentOffset! >= const Duration(seconds: 4),
            ),
            timeout: const Duration(seconds: 15),
            reason: 'Second track did not play beyond the 3-second stall timeout',
          );

          expect(
            errors.where((error) => error.codeEnum == ReadiumErrorCode.audioStreamRetry),
            isEmpty,
            reason: 'Healthy playback after a track change was mistaken for a stall',
          );
          await harness.readium.pause();
        });

        test('audiobook emits ended state when playback reaches end of book', () async {
          final path = harness.fixturePath(
            FixtureKeys.audiobook,
            reason: 'Fixture ${FixtureKeys.audiobook} missing from asset bundle',
          );

          final pub = await harness.readium.openPublication(path);
          expect(pub.readingOrder, isNotEmpty);

          final lastIndex = pub.readingOrder.length - 1;
          final lastLink = pub.readingOrder[lastIndex];
          final lastDuration = lastLink.duration;
          expect(
            lastDuration != null && lastDuration.isFinite && lastDuration > 3,
            isTrue,
            reason:
                'Test requires the last resource to have a finite duration > 3s '
                '(got $lastDuration) to seek near its end',
          );
          final beginSeconds = lastDuration! - 2;

          final states = <ReadiumTimebasedState>[];
          final sub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
          addTearDown(sub.cancel);

          await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0));

          final endLocator = Locator(
            href: lastLink.href,
            type: lastLink.type ?? 'audio/mpeg',
            locations: Locations(
              position: pub.readingOrder.length,
              fragments: ['t=$beginSeconds'],
            ),
          );
          final navigated = await harness.readium.goToLocator(endLocator);
          expect(navigated, isTrue, reason: 'goToLocator to end of last resource should succeed');

          await harness.readium.play(null);

          await waitUntil(
            () => states.any((s) => s.state == TimebasedState.ended),
            timeout: const Duration(seconds: 30),
            reason:
                'Playback reached end of book but no TimebasedState.ended was emitted. '
                'Last state seen: ${states.isEmpty ? "<none>" : states.last.state}',
          );

          await Future<void>.delayed(const Duration(milliseconds: 500));
          expect(
            states.last.state,
            equals(TimebasedState.ended),
            reason:
                'ended was reported but a later state overwrote it as the last emission: '
                '${states.last.state}',
          );

          await harness.readium.pause();
        });

        // Regression: the progression -> time-offset helper resolved the track
        // duration from the *currently playing* locator, so a cross-track jump
        // scaled progression by the wrong track's length.
        test('goToLocator scales progression by the target track, not the playing one', () async {
          final path = harness.fixturePath(
            FixtureKeys.audiobook,
            reason: 'Fixture ${FixtureKeys.audiobook} missing from asset bundle',
          );

          final pub = await harness.readium.openPublication(path);

          final firstDuration = pub.readingOrder.first.duration;
          final targetIndex = pub.readingOrder.length - 1;
          final targetLink = pub.readingOrder[targetIndex];
          final targetDuration = targetLink.duration;
          expect(
            firstDuration != null && targetDuration != null && targetDuration > firstDuration * 2,
            isTrue,
            reason:
                'Test needs the last track to be far longer than the first so the two '
                'candidate offsets are distinguishable (got $firstDuration vs $targetDuration)',
          );

          final states = <ReadiumTimebasedState>[];
          final sub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
          addTearDown(sub.cancel);

          await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0));

          // Start on the first (short) track so it becomes the current locator.
          await harness.readium.play(null);
          await waitUntil(
            () => states.any((s) => s.state == TimebasedState.playing && s.currentOffset != null),
            timeout: const Duration(seconds: 20),
            reason: 'Never reached playing state on the first track',
          );
          await harness.readium.pause();

          // No time fragment: progression is the only offset signal, which is what
          // Publication.resolveLocator now produces for a relocated audiobook locator.
          const progression = 0.5;
          final navigated = await harness.readium.goToLocator(
            Locator(
              href: targetLink.href,
              type: targetLink.type ?? 'audio/mpeg',
              locations: Locations(position: targetIndex + 1, progression: progression),
            ),
          );
          expect(navigated, isTrue, reason: 'goToLocator to the last track should succeed');

          await waitUntil(
            () => states.last.currentLocator?.href == targetLink.href && states.last.currentOffset != null,
            timeout: const Duration(seconds: 20),
            reason: 'Never landed on the target track with an offset',
          );

          final expectedSeconds = targetDuration! * progression;
          final wrongSeconds = firstDuration! * progression;
          final landedSeconds = states.last.currentOffset!.inMilliseconds / 1000.0;

          expect(
            (landedSeconds - expectedSeconds).abs(),
            lessThan((landedSeconds - wrongSeconds).abs()),
            reason:
                'Landed at ${landedSeconds}s: closer to the current-track answer '
                '(${wrongSeconds}s) than to the target-track answer (${expectedSeconds}s)',
          );
          expect(
            landedSeconds,
            greaterThan(wrongSeconds + 1),
            reason: 'Offset was scaled by the first track duration, not the target track',
          );

          await harness.readium.pause();
        });
      },
    );
  });
}
