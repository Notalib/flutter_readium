import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import '../readium_integration_harness.dart';
import '../test_fixtures.dart';
import '../test_suite_setup.dart';

void main() {
  final harness = suiteHarness();

  group('Timebased playback', () {
    testWidgets(
      'EPUB TTS reaches playing with a current locator',
      skip: kIsWeb,
      (_) async {
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

    testWidgets('media-overlay WebPub opens and plays audio on native', (_) async {
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

    testWidgets(
      'native ToC section navigates to its first narrated child',
      skip: kIsWeb,
      (tester) async {
        final path = harness.fixturePath(
          FixtureKeys.tocSectionChild,
          reason: 'Fixture ${FixtureKeys.tocSectionChild} missing from asset bundle',
        );
        final pub = await harness.readium.openPublication(path);
        final tocLink = pub.tocFlattened.singleWhere(
          (link) => link.href == '38533-0002-generic.xhtml#toc-section',
        );
        final locator = pub.locatorFromLink(tocLink)!;
        final textLocators = <Locator>[];
        final textSub = harness.readium.onTextLocatorChanged.listen(textLocators.add);
        addTearDown(textSub.cancel);
        final states = <ReadiumTimebasedState>[];
        final sub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
        addTearDown(sub.cancel);

        await tester.pumpWidget(bareReaderApp(pub));
        await waitWithPump(
          tester,
          () => textLocators.isNotEmpty,
          timeout: firstMountTimeout,
          reason: 'Reader did not emit its initial text locator',
        );
        await harness.readium
            .audioEnable(prefs: AudioPreferences(speed: 1.0))
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => fail('audioEnable did not complete within 30 seconds'),
            );
        final navigated = await harness.readium
            .goToLocator(locator)
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => fail('goToLocator did not complete within 30 seconds'),
            );
        expect(navigated, isTrue, reason: 'goToLocator should find the section\'s first audio cue');
        await harness.readium
            .play(null)
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => fail('play did not complete within 30 seconds'),
            );

        // The ToC targets the section; its first playable cue targets the heading.
        await waitWithPump(
          tester,
          () => states.any(
            (state) =>
                state.currentLocator?.href.endsWith('38533-0002-generic.xhtml') == true &&
                state.currentLocator?.locations?.cssSelector == '#uwlh00008' &&
                state.currentLocator?.locations?.tocHref == tocLink.href,
          ),
          timeout: const Duration(seconds: 30),
          reason: 'Reader did not move to the section\'s first playable text cue',
          diagnostics: () => 'states=$states',
        );
        await waitWithPump(
          tester,
          () => textLocators.any((item) => item.href.endsWith('38533-0002-generic.xhtml')),
          timeout: const Duration(seconds: 30),
          reason: 'Reader view did not navigate from the first chapter to the ToC section',
          diagnostics: () => 'textLocators=$textLocators',
        );

        await harness.readium.pause();
        states.clear();
        expect(
          await harness.readium.goToLocator(
            Locator(
              href: '38533-0002-generic.xhtml',
              type: 'application/xhtml+xml',
              locations: const Locations(fragments: ['t=10']),
            ),
          ),
          isTrue,
        );
        await waitWithPump(
          tester,
          () => states.any(
            (state) =>
                state.currentLocator?.locations?.cssSelector == '#uwlh00011' &&
                state.currentLocator?.locations?.tocHref == tocLink.href,
          ),
          timeout: const Duration(seconds: 30),
          reason: 'Reader did not seek to the later cue in the same section',
        );
        states.clear();
        await harness.readium.goToLocator(
          Locator(
            href: '38533-0002-generic.xhtml',
            type: 'application/xhtml+xml',
            locations: const Locations(cssSelector: '#unknown-anchor'),
          ),
        );
        await harness.readium.play(null);
        await waitWithPump(
          tester,
          () => states.any((state) => state.state == TimebasedState.playing && state.currentOffset != null),
          timeout: const Duration(seconds: 30),
          reason: 'Playback did not resume after the unknown same-resource anchor',
          diagnostics: () => states
              .map((state) => '${state.state}: offset=${state.currentOffset}, locator=${state.currentLocator}')
              .join(' | '),
        );
        final resumed = states.firstWhere(
          (state) => state.state == TimebasedState.playing && state.currentOffset != null,
        );
        expect(
          resumed.currentOffset,
          greaterThanOrEqualTo(const Duration(seconds: 9)),
          reason: 'An unknown same-resource anchor must not rewind audio',
        );
        states.clear();
        expect(await harness.readium.goToLocator(locator), isTrue);
        await waitWithPump(
          tester,
          () => states.any(
            (state) =>
                state.currentLocator?.locations?.cssSelector == '#uwlh00008' &&
                state.currentLocator?.locations?.tocHref == tocLink.href,
          ),
          timeout: const Duration(seconds: 30),
          reason: 'Known same-resource ToC section did not seek back to its first cue',
        );
        states.clear();
        final firstHref = pub.readingOrder.first.href;
        await harness.readium.goToLocator(
          Locator(
            href: firstHref,
            type: 'application/xhtml+xml',
            locations: const Locations(cssSelector: '#unknown-anchor'),
          ),
        );
        await waitWithPump(
          tester,
          () => states.any(
            (state) =>
                state.currentLocator?.href.endsWith(firstHref) == true &&
                state.currentLocator?.locations?.cssSelector == '#uwlh00005' &&
                state.currentOffset != null &&
                state.currentOffset! < const Duration(seconds: 2),
          ),
          timeout: const Duration(seconds: 30),
          reason: 'Unknown cross-resource anchor did not use the first cue fallback',
          diagnostics: () => 'states=$states',
        );
        await harness.readium.pause();
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'Sync Narration restores headings and follows text-resource boundaries',
      skip: kIsWeb,
      (tester) async {
        final path = harness.fixturePath(FixtureKeys.adrSyncOwnership);
        final pub = await harness.readium.openPublication(path);
        final states = <ReadiumTimebasedState>[];
        final sub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
        addTearDown(sub.cancel);
        final textLocators = <Locator>[];
        final textSub = harness.readium.onTextLocatorChanged.listen(textLocators.add);
        addTearDown(textSub.cancel);
        await tester.pumpWidget(bareReaderApp(pub));
        await waitWithPump(
          tester,
          () => textLocators.isNotEmpty,
          timeout: firstMountTimeout,
          reason: 'Synthetic ownership fixture did not mount',
        );
        await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0));
        await harness.readium.play(null);
        await waitWithPump(
          tester,
          () => states.any((state) => state.state == TimebasedState.playing && state.currentOffset != null),
          timeout: const Duration(seconds: 30),
          reason: 'Synthetic narration did not start playing',
          diagnostics: () => 'states=$states',
        );

        final cases = <({int time, String href, String selector, String owner})>[
          (time: 7, href: 'one.xhtml', selector: '#paragraph-b', owner: 'one.xhtml#heading-b'),
          (time: 9, href: 'one.xhtml', selector: '#after-wrapper', owner: 'one.xhtml#heading-a'),
          (time: 11, href: 'one.xhtml', selector: '#inside-section', owner: 'one.xhtml#shared-section'),
          (time: 13, href: 'one.xhtml', selector: '#after-container', owner: 'one.xhtml#heading-a'),
          (time: 15, href: 'two.xhtml', selector: '#boundary', owner: 'two.xhtml'),
          (time: 17, href: 'two.xhtml', selector: '#inside-section', owner: 'two.xhtml#shared-section'),
          (time: 19, href: 'two.xhtml', selector: '#after-boundary', owner: 'two.xhtml'),
        ];
        for (final item in cases) {
          states.clear();
          await harness.readium.goToLocator(
            Locator(
              href: item.href,
              type: 'application/xhtml+xml',
              locations: Locations(fragments: ['t=${item.time}']),
            ),
          );
          await waitWithPump(
            tester,
            () => states.any(
              (state) =>
                  state.currentLocator?.href.endsWith(item.href) == true &&
                  state.currentLocator?.locations?.cssSelector == item.selector &&
                  state.currentLocator?.locations?.tocHref == item.owner,
            ),
            timeout: const Duration(seconds: 30),
            reason: 'Wrong section at ${item.href}:${item.time}s; expected ${item.owner}',
            diagnostics: () => 'states=$states',
          );
        }

        states.clear();
        final repeatedSection = pub.tocFlattened.singleWhere((link) => link.href == 'two.xhtml#shared-section');
        final repeatedLocator = pub.locatorFromLink(repeatedSection)!;
        await harness.readium.goToLocator(repeatedLocator);
        await waitWithPump(
          tester,
          () => states.any(
            (state) =>
                state.currentLocator?.href.endsWith('two.xhtml') == true &&
                state.currentLocator?.locations?.cssSelector == '#inside-section' &&
                state.currentLocator?.locations?.tocHref == repeatedSection.href &&
                state.currentOffset != null &&
                state.currentOffset! >= const Duration(seconds: 16) &&
                state.currentOffset! < const Duration(seconds: 18),
          ),
          timeout: const Duration(seconds: 30),
          reason: 'Repeated structural ID selected the first resource instead of the second',
          diagnostics: () =>
              'request=${repeatedLocator.toJson()}, states=${states.map((state) => state.toJson()).toList()}',
        );
        await harness.readium.pause();
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'Sync Narration resolves ToC targets the narration does not list',
      skip: kIsWeb,
      (tester) async {
        final path = harness.fixturePath(FixtureKeys.syntheticNewspaper);
        final pub = await harness.readium.openPublication(path);
        final states = <ReadiumTimebasedState>[];
        final sub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
        addTearDown(sub.cancel);
        final textLocators = <Locator>[];
        final textSub = harness.readium.onTextLocatorChanged.listen(textLocators.add);
        addTearDown(textSub.cancel);
        await tester.pumpWidget(bareReaderApp(pub));
        await waitWithPump(
          tester,
          () => textLocators.isNotEmpty,
          timeout: firstMountTimeout,
          reason: 'Synthetic newspaper did not mount',
        );
        Future<void> expectCue(String resource, String cue, String? owner, {int? offset}) async {
          // Busy simulators can deliver state after playback has advanced within the cue.
          bool matches(ReadiumTimebasedState state) =>
              state.currentLocator?.href.endsWith(resource) == true &&
              state.currentLocator?.locations?.cssSelector == cue &&
              state.currentLocator?.locations?.tocHref == owner &&
              (offset == null ||
                  (state.currentOffset != null &&
                      state.currentOffset! >= Duration(seconds: offset) &&
                      state.currentOffset! < Duration(seconds: offset + 10)));
          await waitWithPump(
            tester,
            () => states.any(matches),
            timeout: const Duration(seconds: 30),
            reason: 'Expected $resource $cue with owner $owner',
            diagnostics: () => states
                .map(
                  (state) =>
                      '${state.currentLocator?.href} ${state.currentLocator?.locations?.cssSelector} owner=${state.currentLocator?.locations?.tocHref} offset=${state.currentOffset}',
                )
                .join(' | '),
          );
          if (offset != null) {
            final actual = states.firstWhere(matches).currentOffset;
            expect(actual, isNotNull);
            expect(actual, greaterThanOrEqualTo(Duration(seconds: offset)));
            expect(actual, lessThan(Duration(seconds: offset + 10)));
          }
        }

        Locator target(String href) => pub.locatorFromLink(pub.tocFlattened.singleWhere((link) => link.href == href))!;

        // Initial-locator mapping must skip the prelude and the cue-less heading.
        await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0), fromLocator: target('np-0001.xhtml#e2'));
        await harness.readium.play(null);
        await expectCue('np-0001.xhtml', '#e4', 'np-0001.xhtml#e4', offset: 10);
        await harness.readium.pause();

        states.clear();
        await harness.readium.goToLocator(
          Locator(
            href: 'np-0001.xhtml',
            type: 'application/xhtml+xml',
            locations: const Locations(fragments: ['t=0']),
          ),
        );
        await harness.readium.play(null);
        await expectCue('np-0001.xhtml', '#prelude', null, offset: 0);

        // The section shares its first cue with the deeper heading. Empty-heading
        // and section seeks must stay identical after owner enrichment has run.
        for (final href in ['np-0001.xhtml#e2', 'np-0001.xhtml#e3']) {
          states.clear();
          await harness.readium.goToLocator(target(href));
          await harness.readium.play(null);
          await expectCue('np-0001.xhtml', '#e4', 'np-0001.xhtml#e4', offset: 10);
        }

        states.clear();
        await harness.readium.goToLocator(
          Locator(
            href: 'np-0001.xhtml',
            type: 'application/xhtml+xml',
            locations: const Locations(cssSelector: '#missing'),
          ),
        );
        await harness.readium.play(null);
        await expectCue('np-0001.xhtml', '#e4', 'np-0001.xhtml#e4', offset: 10);

        // Main section and aside resolve within the same audio track in both directions.
        final cases = <({String toc, String cue, int offset})>[
          (toc: 'np-0011.xhtml#e198', cue: '#e199', offset: 10),
          (toc: 'np-0011.xhtml#e166', cue: '#e168', offset: 0),
          (toc: 'np-0011.xhtml#e198', cue: '#e199', offset: 10),
        ];
        for (final item in cases) {
          states.clear();
          expect(await harness.readium.goToLocator(target(item.toc)), isTrue);
          await expectCue('np-0011.xhtml', item.cue, item.toc, offset: item.offset);
        }
        await harness.readium.play(null);
        await expectCue('np-0011.xhtml', '#e200', 'np-0011.xhtml#e198', offset: 20);

        states.clear();
        await harness.readium.skipToNextTOC(publication: pub, currentTocHref: 'np-0011.xhtml#e198');
        await expectCue('np-0012.xhtml', '#e204', 'np-0012.xhtml#e202', offset: 0);
        states.clear();
        await harness.readium.skipToPreviousTOC(publication: pub, currentTocHref: 'np-0012.xhtml#e202');
        await expectCue('np-0011.xhtml', '#e199', 'np-0011.xhtml#e198', offset: 10);
        await harness.readium.pause();
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'media-overlay WebPub initializes synchronized text cues on web',
      skip: !kIsWeb,
      (tester) async {
        final path = harness.fixturePath(
          FixtureKeys.overlayWebpub,
          reason: 'Fixture ${FixtureKeys.overlayWebpub} missing from asset bundle',
        );
        final pub = await harness.readium.openPublication(path);

        final textLocators = <Locator>[];
        final textSub = harness.readium.onTextLocatorChanged.listen(textLocators.add);
        addTearDown(textSub.cancel);
        final states = <ReadiumTimebasedState>[];
        final stateSub = harness.readium.onTimebasedPlayerStateChanged.listen(states.add);
        addTearDown(stateSub.cancel);

        await tester.pumpWidget(bareReaderApp(pub));
        await waitWithPump(
          tester,
          () => textLocators.isNotEmpty,
          timeout: firstMountTimeout,
          reason: 'Media-overlay reader emitted no initial text location on web',
        );
        textLocators.clear();

        await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0));
        await harness.readium.play(null);
        await waitWithPump(
          tester,
          () =>
              states.any((state) => state.currentLocator?.locations?.fragments.isNotEmpty ?? false) &&
              textLocators.isNotEmpty,
          timeout: const Duration(seconds: 30),
          reason: 'Web Media Overlay emitted no synchronized audio/text cue',
          diagnostics: () =>
              'states=${states.map((state) => '${state.state}:${state.currentLocator}').toList()}, '
              'textLocators=$textLocators',
        );

        final cueLocator = states
            .lastWhere(
              (state) => state.currentLocator?.locations?.fragments.isNotEmpty ?? false,
            )
            .currentLocator!;
        expect(
          textLocators.any((locator) => locator.href == cueLocator.href),
          isTrue,
          reason: 'The visual reader did not follow the Media Overlay cue resource',
        );

        await harness.readium.pause();
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('audiobook opens and plays audio on native', (_) async {
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
        testWidgets('audiobook pause then resume cycles through state transitions', (_) async {
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

        testWidgets('audioSeekBy advances the timebased position', (_) async {
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

        testWidgets('changing audiobook tracks does not trigger false stall recovery', (_) async {
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
          final errorsBeforeTrackChange = errors.length;

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
            _retriesAfter(errors, errorsBeforeTrackChange),
            isEmpty,
            reason: 'Healthy playback after a track change was mistaken for a stall',
          );
          await harness.readium.pause();
        });

        testWidgets('pause and backward seek do not trigger false stall recovery', (_) async {
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
          final errorsBeforePause = errors.length;

          await harness.readium.pause();
          await Future<void>.delayed(const Duration(seconds: 3));
          expect(
            _retriesAfter(errors, errorsBeforePause),
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
            _retriesAfter(errors, errorsBeforePause),
            isEmpty,
            reason: 'Healthy playback after a backward seek was mistaken for a stall',
          );
          await harness.readium.pause();
        });

        testWidgets('audiobook emits ended state when playback reaches end of book', (_) async {
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

          // The 1s stall timeout must be short enough to fire inside the 2s window after `ended`. It
          // then also fires whenever CI starts playback slowly, so count retries from proven progress on.
          final begin = Duration(milliseconds: (beginSeconds * 1000).round());
          await waitUntil(
            () => states.any(
              (s) =>
                  s.state == TimebasedState.playing &&
                  s.currentLocator?.href == lastLink.href &&
                  s.currentOffset != null &&
                  s.currentOffset! >= begin + const Duration(milliseconds: 500),
            ),
            timeout: const Duration(seconds: 15),
            reason: 'Last track never played past its start offset',
          );
          final errorsBeforeProgress = errors.length;

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
            _retriesAfter(errors, errorsBeforeProgress),
            isEmpty,
            reason: 'Final ended state must cancel resource-loading recovery',
          );

          await harness.readium.pause();
        });

        // Regression: the progression -> time-offset helper resolved the track
        // duration from the *currently playing* locator, so a cross-track jump
        // scaled progression by the wrong track's length.
        testWidgets('goToLocator scales progression by the target track, not the playing one', (_) async {
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
        testWidgets(
          'media-overlay goToLocator lands the text position on the jumped-to chapter',
          skip: defaultTargetPlatform != TargetPlatform.iOS,
          (_) async {
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

    // Audio must start from the manifest alone, before any reader view exists —
    // that is how the host app plays a book without showing it. Each fixture here
    // is a different cue shape, and a parser that drops one of them emits no
    // playback state at all, which is what these assertions catch.
    group('audio starts without a reader view', () {
      test('guided-navigation WebPub', () async {
        final path = harness.fixturePath(
          FixtureKeys.guidedNav,
          reason: 'Fixture ${FixtureKeys.guidedNav} missing from asset bundle',
        );

        await harness.readium.openPublication(path);

        await expectAudioSessionStarts(
          harness.readium,
          enable: () => harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0)),
          reason: 'Guided-navigation cues produced no audio session',
        );
      });

      test('DiViNa comic', () async {
        final path = harness.fixturePath(
          FixtureKeys.divina,
          reason: 'Fixture ${FixtureKeys.divina} missing from asset bundle',
        );

        await harness.readium.openPublication(path);

        await expectAudioSessionStarts(
          harness.readium,
          enable: () => harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0)),
          reason:
              'DiViNa cues carry an imgref and no textref; a parser that requires '
              'a text reference drops them all and starts no audio session',
        );
      });

      test('comic media-overlay EPUB', () async {
        final path = harness.fixturePath(
          FixtureKeys.comic,
          reason: 'Fixture ${FixtureKeys.comic} missing from asset bundle',
        );

        await harness.readium.openPublication(path);

        await expectAudioSessionStarts(
          harness.readium,
          enable: () => harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0)),
          reason: 'Comic media-overlay cues produced no audio session',
        );
      });

      testWidgets('a session started first survives the reader mounting after it', (tester) async {
        final path = harness.fixturePath(
          FixtureKeys.guidedNav,
          reason: 'Fixture ${FixtureKeys.guidedNav} missing from asset bundle',
        );

        final pub = await harness.readium.openPublication(path);

        await expectAudioSessionStarts(
          harness.readium,
          enable: () => harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0)),
          reason: 'Guided-navigation cues produced no audio session',
        );

        final locators = <Locator>[];
        final sub = harness.readium.onTextLocatorChanged.listen(locators.add);
        addTearDown(sub.cancel);

        await tester.pumpWidget(bareReaderApp(pub));
        await waitWithPump(
          tester,
          () => locators.isNotEmpty,
          timeout: firstMountTimeout,
          reason: 'Reader mounted after audio started but reported no location',
        );

        await tester.pumpWidget(const SizedBox());
      });
    });
  });
}

/// Compare chapters by filename: a text locator and its reading-order link can carry
/// different base-path prefixes for the same file.
String _chapterFile(String href) => href.split('#').first.split('?').first.split('/').last;

/// `audioStreamRetry` errors after the first [skip] errors. The stall tests count from proven playback on:
/// CI can take longer than their short stall timeouts to start cold playback, which is a real stall.
Iterable<ReadiumError> _retriesAfter(List<ReadiumError> errors, int skip) =>
    errors.skip(skip).where((error) => error.codeEnum == ReadiumErrorCode.audioStreamRetry);
