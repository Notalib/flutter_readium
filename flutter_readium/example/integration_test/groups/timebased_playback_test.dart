import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';
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
            const AudioRecoveryPolicy(
              stallTimeoutSeconds: 3.0,
              recoverOnResourceLoadingTimeout: true,
            ),
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

        test('pause and backward seek do not trigger false stall recovery', () async {
          await harness.readium.setAudioRecoveryPolicy(
            const AudioRecoveryPolicy(
              stallTimeoutSeconds: 2.0,
              recoverOnResourceLoadingTimeout: true,
            ),
          );
          addTearDown(
            () => harness.readium.setAudioRecoveryPolicy(const AudioRecoveryPolicy()),
          );

          final path = harness.fixturePath(
            FixtureKeys.audiobook,
            reason: 'Fixture ${FixtureKeys.audiobook} missing from asset bundle',
          );
          await harness.readium.openPublication(path);

          final states = <ReadiumTimebasedState>[];
          final errors = <ReadiumError>[];
          final stateSub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
          final errorSub = harness.readium.onErrorEvent.listen(errors.add);
          addTearDown(stateSub.cancel);
          addTearDown(errorSub.cancel);

          await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0));
          await harness.readium.play(null);
          await waitUntil(
            () =>
                states.isNotEmpty &&
                states.last.state == TimebasedState.playing &&
                (states.last.currentOffset ?? Duration.zero) >= const Duration(seconds: 3),
            timeout: const Duration(seconds: 10),
            reason: 'Playback did not advance before the pause check',
          );

          await harness.readium.pause();
          await Future<void>.delayed(const Duration(seconds: 3));
          expect(
            errors.where((error) => error.codeEnum == ReadiumErrorCode.audioStreamRetry),
            isEmpty,
            reason: 'An explicit pause was mistaken for a stall',
          );

          await harness.readium.resume();
          await waitUntil(
            () =>
                states.isNotEmpty &&
                states.last.state == TimebasedState.playing &&
                (states.last.currentOffset ?? Duration.zero) >= const Duration(seconds: 4),
            timeout: const Duration(seconds: 10),
            reason: 'Playback did not resume before the backward seek check',
          );

          final beforeSeek = states.last.currentOffset!;
          await harness.readium.audioSeekBy(const Duration(seconds: -2));
          await harness.readium.resume();
          await waitUntil(
            () =>
                states.isNotEmpty &&
                states.last.state == TimebasedState.playing &&
                states.last.currentOffset != null &&
                states.last.currentOffset! < beforeSeek - const Duration(seconds: 1),
            timeout: const Duration(seconds: 10),
            reason: 'Playback did not move backward after audioSeekBy',
          );
          final afterSeek = states.last.currentOffset!;

          await waitUntil(
            () =>
                states.isNotEmpty &&
                states.last.state == TimebasedState.playing &&
                (states.last.currentOffset ?? Duration.zero) >= afterSeek + const Duration(seconds: 5),
            timeout: const Duration(seconds: 10),
            reason: 'Playback did not continue for two stall timeouts after seeking',
          );
          expect(
            errors.where((error) => error.codeEnum == ReadiumErrorCode.audioStreamRetry),
            isEmpty,
            reason: 'Healthy playback after a backward seek was mistaken for a stall',
          );
          await harness.readium.pause();
        });

        test('audiobook emits ended state when playback reaches end of book', () async {
          await harness.readium.setAudioRecoveryPolicy(
            const AudioRecoveryPolicy(
              stallTimeoutSeconds: 1.0,
              recoverOnResourceLoadingTimeout: true,
            ),
          );
          addTearDown(
            () => harness.readium.setAudioRecoveryPolicy(const AudioRecoveryPolicy()),
          );

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
          final errors = <ReadiumError>[];
          final sub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
          final errorSub = harness.readium.onErrorEvent.listen(errors.add);
          addTearDown(sub.cancel);
          addTearDown(errorSub.cancel);

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

          await Future<void>.delayed(const Duration(seconds: 2));
          expect(
            states.last.state,
            equals(TimebasedState.ended),
            reason:
                'ended was reported but a later state overwrote it as the last emission: '
                '${states.last.state}',
          );
          expect(
            errors.where((error) => error.codeEnum == ReadiumErrorCode.audioStreamRetry),
            isEmpty,
            reason: 'Final ended state must cancel resource-loading recovery',
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

          // The target track reports a 0 offset before the seek is applied, and a
          // plain non-null check accepted it — the test then read 0.0s and failed.
          // Both candidate answers are non-zero, so requiring > 0 hides nothing.
          ReadiumTimebasedState? landed;
          await waitUntil(
            () {
              final state = states.last;
              if (state.currentLocator?.href != targetLink.href) {
                return false;
              }
              final offset = state.currentOffset;
              if (offset == null || offset <= Duration.zero) {
                return false;
              }
              landed = state;
              return true;
            },
            timeout: const Duration(seconds: 20),
            reason: 'Never landed on the target track with the seek applied (offset stayed 0)',
          );

          final expectedSeconds = targetDuration! * progression;
          final wrongSeconds = firstDuration! * progression;
          final landedSeconds = landed!.currentOffset!.inMilliseconds / 1000.0;

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

        // Exercises the media-overlay goToLocator path end to end: a paused cross-chapter jump
        // routes through seek(toLocator:) -> goBounded (the timeout-bounded wrapper that also
        // carries the `_isNavigating` deadlock guard) and must resolve to success with the
        // reported text position landing on the target chapter. Pausing first means only the
        // jump can move that position, not continuous playback. The on-page highlight decoration
        // is webview-only, so a headless test asserts the reported locator, not the decoration.
        // iOS-only: goBounded and its guard are iOS; Android media-overlay sync differs.
        test(
          'media-overlay goToLocator lands the text position on the jumped-to chapter',
          skip: defaultTargetPlatform != TargetPlatform.iOS
              ? 'Exercises the iOS goBounded media-overlay path; Android syncs differently'
              : false,
          () async {
            final path = harness.fixturePath(
              FixtureKeys.overlayWebpub,
              reason: 'Fixture ${FixtureKeys.overlayWebpub} missing from asset bundle',
            );

            final pub = await harness.readium.openPublication(path);
            expect(
              pub.containsMediaOverlays,
              isTrue,
              reason: 'Overlay webpub should report media overlays',
            );
            expect(
              pub.readingOrder.length,
              greaterThanOrEqualTo(2),
              reason: 'Test needs a later chapter to jump to (got ${pub.readingOrder.length})',
            );

            final states = <ReadiumTimebasedState>[];
            final sub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
            addTearDown(sub.cancel);

            await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0));
            await harness.readium.play(null);

            // Media overlay reports the combined text locator on currentLocator.
            await waitUntil(
              () => states.any((s) => s.state == TimebasedState.playing && s.currentLocator?.href != null),
              timeout: const Duration(seconds: 30),
              reason: 'Never reached playing with a media-overlay text locator',
            );

            // Pause so continuous playback cannot advance the href; then only the jump can.
            await harness.readium.pause();
            // A paused-state emission can carry a null locator, so take the last state that
            // actually reported a text position rather than `states.last`.
            final beforeJumpHref = states.lastWhere((s) => s.currentLocator?.href != null).currentLocator!.href;

            // Last chapter is unreachable in the first seconds, so it always differs from
            // where we paused. goToLocator with audio enabled routes through
            // seek(toLocator:) -> goBounded, i.e. the guarded path under test.
            final targetChapter = pub.readingOrder.last;
            final navigated = await harness.readium.goToLocator(
              Locator(
                href: targetChapter.href,
                type: targetChapter.type ?? 'text/html',
                locations: const Locations(progression: 0.25),
              ),
            );
            expect(
              navigated,
              isTrue,
              reason: 'goToLocator to a later media-overlay chapter should succeed',
            );

            await waitUntil(
              () => states.last.currentLocator?.href != null && states.last.currentLocator!.href != beforeJumpHref,
              timeout: const Duration(seconds: 20),
              reason:
                  'Reported text position did not move off $beforeJumpHref after goToLocator '
                  '(last=${states.isEmpty ? "<none>" : states.last.currentLocator?.href}); '
                  'the media-overlay jump did not land.',
            );

            expect(
              _chapterFile(states.last.currentLocator!.href),
              equals(_chapterFile(targetChapter.href)),
              reason:
                  'Highlight moved but not to the jumped-to chapter '
                  '(${states.last.currentLocator!.href} vs ${targetChapter.href})',
            );

            await harness.readium.pause();
          },
        );

        // Regression: while `_isNavigating` suppresses the delegate, nothing reports where the
        // jump landed, and a paused jump gets no periodic tick to report it later — so the reader
        // page stayed on the pre-jump chapter until playback resumed. With audio enabled
        // `goToLocator` goes to the timebased navigator, never to the reader view, so the page can
        // only move via the navigator's reachedLocator -> syncToLocator report.
        // iOS-only: this reporting lives in the iOS navigator; Android syncs via its own path.
        testWidgets(
          'media-overlay goToLocator syncs the reader page when paused',
          // testWidgets takes a bool skip, so the reason lives in the comment above.
          skip: defaultTargetPlatform != TargetPlatform.iOS,
          (tester) async {
            final path = harness.fixturePath(
              FixtureKeys.overlayWebpub,
              reason: 'Fixture ${FixtureKeys.overlayWebpub} missing from asset bundle',
            );

            final pub = await harness.readium.openPublication(path);
            expect(
              pub.readingOrder.length,
              greaterThanOrEqualTo(2),
              reason: 'Test needs a later chapter to jump to (got ${pub.readingOrder.length})',
            );

            final locators = <Locator>[];
            final sub = harness.readium.onTextLocatorChanged.listen(locators.add);
            addTearDown(sub.cancel);

            final states = <ReadiumTimebasedState>[];
            final stateSub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
            addTearDown(stateSub.cancel);

            ReadiumReaderStatus? readerStatus;
            final readerStatusSub = harness.readium.onReaderStatusChanged.listen((s) => readerStatus = s);
            addTearDown(readerStatusSub.cancel);

            await tester.pumpWidget(bareReaderApp(pub));
            await waitWithPump(
              tester,
              () => locators.isNotEmpty,
              timeout: firstMountTimeout,
              reason: 'No initial textLocator emitted',
              diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
            );

            await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0));
            await harness.readium.play(null);
            await waitWithPump(
              tester,
              () => states.any((s) => s.state == TimebasedState.playing),
              timeout: const Duration(seconds: 30),
              reason: 'media-overlay never reached playing',
              diagnostics: () => 'lastState=${states.isEmpty ? "<none>" : states.last.state}',
            );

            // Paused: nothing re-reports position, so only the jump can move the reader page.
            await harness.readium.pause();
            await waitForListStable(tester, locators);
            final beforeJump = locators.last;

            final targetChapter = pub.readingOrder.last;
            final navigated = await harness.readium.goToLocator(
              Locator(
                href: targetChapter.href,
                type: targetChapter.type ?? 'text/html',
                locations: const Locations(progression: 0.25),
              ),
            );
            expect(navigated, isTrue, reason: 'goToLocator to a later chapter should succeed');

            await waitWithPump(
              tester,
              () => locators.last != beforeJump,
              timeout: const Duration(seconds: 30),
              reason:
                  'Reader page did not sync after a paused media-overlay jump '
                  '(still ${beforeJump.href}); the landed location was never reported.',
            );
            await waitForListStable(tester, locators);

            expect(
              _chapterFile(locators.last.href),
              equals(_chapterFile(targetChapter.href)),
              reason:
                  'Reader synced but not to the jumped-to chapter '
                  '(${locators.last.href} vs ${targetChapter.href})',
            );

            await harness.readium.pause();
            await tester.pumpWidget(const SizedBox());
          },
        );
      },
    );
  });
}

/// Compare chapters by filename: a text locator and its reading-order link can carry
/// different base-path prefixes for the same file.
String _chapterFile(String href) => href.split('#').first.split('?').first.split('/').last;
