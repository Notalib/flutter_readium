import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import '../readium_integration_harness.dart';
import '../unreachable_audiobook_fixture.dart' if (dart.library.js_interop) '../unreachable_audiobook_fixture_web.dart';

void defineErrorHandlingTests(ReadiumIntegrationHarness harness) {
  group('Error handling', () {
    test(
      'openPublication throws ReadiumException for an invalid native path',
      skip: kIsWeb ? 'Error path differs on web (HTTP fetch vs file I/O)' : null,
      () async {
        await expectLater(
          harness.readium.openPublication('/does-not-exist/no-such.epub'),
          throwsA(isA<ReadiumException>()),
        );
      },
    );

    test(
      'onErrorEvent emits when opening an unreachable web publication',
      skip: kIsWeb ? null : 'Web-specific HTTP error event path',
      () async {
        final errors = <ReadiumError>[];
        final sub = harness.readium.onErrorEvent.listen(errors.add);
        addTearDown(sub.cancel);

        try {
          await harness.readium.openPublication('/no-such-fixture/manifest.json');
        } on Object {
          // Expected: open fails; this test asserts the error event stream.
        }

        await waitUntil(
          () => errors.isNotEmpty,
          timeout: const Duration(seconds: 15),
          reason: 'onErrorEvent did not emit after a failed openPublication',
        );
      },
    );

    // Exercises the audio-stream recovery loop's terminal path end-to-end: an
    // audiobook whose media host is unreachable can never connect, so recovery
    // runs its bounded attempts and then emits a terminal audioStream error +
    // failure state. This covers the initNavigator-bound -> recovery -> terminal
    // path that native unit tests can't (they don't drive a real player), and
    // would have caught the iOS inert-timeout and web controller-clobber
    // regressions.
    //
    // Native-only: forcing this deterministically on web means a browser
    // MediaError, which is validated separately in the web jest suite. The
    // mid-stream throttle case (retry-while-playing) still needs real network
    // fault injection (Link Conditioner) and stays a manual check.
    test(
      'unreachable audiobook media surfaces a terminal audioStream error via recovery',
      skip: kIsWeb ? 'Native-only: web audio failure path is covered by jest' : null,
      () async {
        // 127.0.0.1:1 refuses connections immediately and deterministically, so
        // each recovery attempt fails fast rather than waiting out a timeout.
        const deadHost = 'http://127.0.0.1:1/frx-recovery-test';
        final manifest = jsonEncode({
          '@context': 'https://readium.org/webpub-manifest/context.jsonld',
          'metadata': {
            '@type': 'http://schema.org/Audiobook',
            'conformsTo': 'https://readium.org/webpub-manifest/profiles/audiobook',
            'title': 'Unreachable audiobook (recovery test)',
            'language': 'en',
            'duration': 60,
          },
          'links': [
            {
              'rel': 'self',
              'href': '$deadHost/manifest.json',
              'type': 'application/audiobook+json',
            },
          ],
          'readingOrder': [
            {
              'href': '$deadHost/track1.mp3',
              'type': 'audio/mpeg',
              'duration': 60,
              'title': 'Track 1',
            },
          ],
        });

        // Bound the loop hard so the test finishes in a few seconds: 2 attempts,
        // ~0.1s + 0.2s backoff, short connect/stall windows. The policy applies
        // to the next-opened publication, so set it before openPublication.
        await harness.readium.setAudioRecoveryPolicy(
          const AudioRecoveryPolicy(
            maxAttempts: 2,
            backoffBaseSeconds: 0.1,
            connectionTimeoutSeconds: 2.0,
            stallTimeoutSeconds: 3.0,
          ),
        );
        addTearDown(() => harness.readium.setAudioRecoveryPolicy(const AudioRecoveryPolicy()));

        final errors = <ReadiumError>[];
        final sub = harness.readium.onErrorEvent.listen(errors.add);
        addTearDown(sub.cancel);

        final manifestPath = await writeTempAudiobookManifest(manifest);
        final pub = await harness.readium.openPublication(manifestPath);
        expect(
          pub.conformsToReadiumAudiobook,
          isTrue,
          reason: 'Synthetic manifest should open as a Readium audiobook',
        );

        await harness.readium.audioEnable(prefs: AudioPreferences(speed: 1.0));
        await harness.readium.play(null);

        // Generous budget over the 2 bounded attempts (backoff + connect).
        await waitUntil(
          () => errors.any(
            (e) => e.codeEnum.category == ReadiumErrorCategory.audioStream && e.codeEnum.isFatal,
          ),
          timeout: const Duration(seconds: 30),
          reason:
              'Recovery never emitted a terminal audioStream error for an '
              'unreachable media host (saw: ${errors.map((e) => e.code ?? e.codeEnum.name).toList()})',
        );

        final terminal = errors.firstWhere(
          (e) => e.codeEnum.category == ReadiumErrorCategory.audioStream && e.codeEnum.isFatal,
        );
        expect(
          terminal.codeEnum,
          ReadiumErrorCode.audioStreamNetworkError,
          reason: 'An unreachable host is a network-class failure',
        );
      },
    );
  });
}
