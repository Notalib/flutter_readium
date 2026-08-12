import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Locator serialisation
  // ---------------------------------------------------------------------------
  group('Locator', () {
    final locator = Locator(
      href: '/OEBPS/chapter1.xhtml',
      type: 'application/xhtml+xml',
      title: 'Chapter 1',
      locations: Locations(
        progression: 0.42,
        totalProgression: 0.07,
        position: 14,
        cssSelector: '#p42',
      ),
      text: LocatorText(
        before: 'before',
        highlight: 'highlight',
        after: 'after',
      ),
    );

    test('round-trips through toJson / fromJson', () {
      final json = locator.toJson();
      final restored = Locator.fromJson(json);
      expect(restored, locator);
    });

    test('round-trips through json string', () {
      final jsonString = jsonEncode(locator.toJson());
      final restored = Locator.fromJsonString(jsonString);
      expect(restored, locator);
    });

    test('locations.progression is preserved', () {
      final json = locator.toJson();
      final restored = Locator.fromJson(json);
      expect(restored?.locations?.progression, closeTo(0.42, 1e-6));
    });

    test('locations.totalProgression is preserved', () {
      final json = locator.toJson();
      final restored = Locator.fromJson(json);
      expect(restored?.locations?.totalProgression, closeTo(0.07, 1e-6));
    });

    test('minimal locator round-trips href and type', () {
      final minimal = Locator(href: '/ch.xhtml', type: 'application/xhtml+xml');
      final restored = Locator.fromJson(minimal.toJson());
      expect(restored?.href, '/ch.xhtml');
      expect(restored?.type, 'application/xhtml+xml');
    });
  });

  // ---------------------------------------------------------------------------
  // EPUBPreferences serialisation
  // ---------------------------------------------------------------------------
  group('EPUBPreferences', () {
    test('round-trips preventMOColumnBreaks: true through toJson / fromJson', () {
      const prefs = EPUBPreferences(preventMOColumnBreaks: true);
      final restored = EPUBPreferences.fromJson(prefs.toJson());
      expect(restored.preventMOColumnBreaks, isTrue);
    });

    test('round-trips preventMOColumnBreaks: false through toJson / fromJson', () {
      const prefs = EPUBPreferences(preventMOColumnBreaks: false);
      final restored = EPUBPreferences.fromJson(prefs.toJson());
      expect(restored.preventMOColumnBreaks, isFalse);
    });

    test('toJson emits preventMOColumnBreaks under the correct key', () {
      const prefs = EPUBPreferences(preventMOColumnBreaks: false);
      final json = prefs.toJson();
      expect(json.containsKey('preventMOColumnBreaks'), isTrue);
      expect(json['preventMOColumnBreaks'], isFalse);
    });

    test('fromJson defaults preventMOColumnBreaks to true when key is absent', () {
      final restored = EPUBPreferences.fromJson({});
      expect(restored.preventMOColumnBreaks, isTrue);
    });

    test('copyWith preserves preventMOColumnBreaks when not overridden', () {
      const prefs = EPUBPreferences(preventMOColumnBreaks: false);
      final copied = prefs.copyWith();
      expect(copied.preventMOColumnBreaks, isFalse);
    });

    test('copyWith overrides preventMOColumnBreaks', () {
      const prefs = EPUBPreferences(preventMOColumnBreaks: false);
      final copied = prefs.copyWith(preventMOColumnBreaks: true);
      expect(copied.preventMOColumnBreaks, isTrue);
    });

    test('equality distinguishes preventMOColumnBreaks values', () {
      const a = EPUBPreferences(preventMOColumnBreaks: true);
      const b = EPUBPreferences(preventMOColumnBreaks: false);
      expect(a, isNot(equals(b)));
    });
  });

  group('PDFPreferences', () {
    const prefs = PDFPreferences(
      layout: PDFLayout.scrollVertical,
      readingProgression: PDFReadingProgression.rtl,
      pageSpacing: 12.5,
      fit: PDFFit.page,
    );

    test('round-trips through toJson / fromJson', () {
      final restored = PDFPreferences.fromJson(prefs.toJson());
      expect(restored, prefs);
    });

    test('fromJson supports numeric pageSpacing and fit enum', () {
      final restored = PDFPreferences.fromJson({
        'layout': 'paginated',
        'readingProgression': 'ltr',
        'pageSpacing': 8,
        'fit': 'auto',
      });
      expect(restored.layout, PDFLayout.paginated);
      expect(restored.readingProgression, PDFReadingProgression.ltr);
      expect(restored.pageSpacing, 8.0);
      expect(restored.fit, PDFFit.auto);
    });
  });

  // ---------------------------------------------------------------------------
  // ReadiumException
  // ---------------------------------------------------------------------------
  group('ReadiumException', () {
    test('toString includes message', () {
      final e = ReadiumException(ReadiumError('something failed'));
      expect(e.toString(), contains('something failed'));
    });

    test('fromError wraps arbitrary errors', () {
      final e = ReadiumException.fromError(Exception('boom'));
      expect(e, isA<ReadiumException>());
      expect(e.message, contains('boom'));
    });

    test('fromPlatformException preserves structured error fields', () {
      final e = ReadiumException.fromPlatformException(
        PlatformException(
          code: 'notFound',
          message: 'Publication not found',
          details: {'href': '/pub.epub', 'httpStatus': 404, 'message': 'native detail'},
        ),
      );

      expect(e.message, 'Publication not found');
      expect(e.code, 'notFound');
      expect(e.codeEnum, ReadiumErrorCode.notFound);
      expect(e.href, '/pub.epub');
      expect(e.httpStatus, 404);
    });
  });

  group('ReadiumError', () {
    test('equality is based on message, code, and details', () {
      final a = ReadiumError('oops', code: '42');
      final b = ReadiumError('oops', code: '42');
      expect(a, equals(b));

      final firstRetry = ReadiumError(
        'retrying',
        code: 'AudioStreamRetry',
        details: {'attempt': 1, 'maxAttempts': 3},
      );
      final secondRetry = ReadiumError(
        'retrying',
        code: 'AudioStreamRetry',
        details: {'attempt': 2, 'maxAttempts': 3},
      );
      expect(firstRetry, isNot(secondRetry));
    });

    test('round-trips through toJson / fromJson', () {
      final error = ReadiumError(
        'oops',
        code: '42',
        details: {'href': '/ch1.mp3', 'attempt': 1, 'maxAttempts': 3, 'httpStatus': 503},
      );
      final restored = ReadiumError.fromJson(error.toJson());
      expect(restored.message, 'oops');
      expect(restored.code, '42');
      expect(restored.href, '/ch1.mp3');
      expect(restored.attempt, 1);
      expect(restored.maxAttempts, 3);
      expect(restored.httpStatus, 503);
    });

    test('details is null when omitted', () {
      final error = ReadiumError.fromJson({'message': 'oops', 'code': '42'});
      expect(error.details, isNull);
      expect(error.href, isNull);
      expect(error.attempt, isNull);
      expect(error.maxAttempts, isNull);
      expect(error.httpStatus, isNull);
    });

    test('tolerates a legacy freeform-string data payload by wrapping it as message', () {
      final error = ReadiumError.fromJson({
        'message': 'oops',
        'code': '42',
        'data': 'attempt=1/3 href=/ch1.mp3',
      });
      expect(error.details, {'message': 'attempt=1/3 href=/ch1.mp3'});
      expect(error.href, isNull);
    });

    test('ignores legacy stackTrace payload from stale producers', () {
      final error = ReadiumError.fromJson({
        'message': 'oops',
        'code': 'notFound',
        'stackTrace': 'native stack',
      });

      expect(error.message, 'oops');
      expect(error.code, 'notFound');
      expect(error.toJson().containsKey('stackTrace'), isFalse);
    });

    test('toJson omits data when details is null', () {
      final error = ReadiumError('oops', code: '42');
      expect(error.toJson().containsKey('data'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // TimebasedState enum
  // ---------------------------------------------------------------------------
  group('TimebasedState', () {
    test('fromString returns matching value', () {
      expect(TimebasedState.fromString('playing'), TimebasedState.playing);
      expect(TimebasedState.fromString('paused'), TimebasedState.paused);
      expect(TimebasedState.fromString('ended'), TimebasedState.ended);
    });

    test('fromString is case-insensitive', () {
      expect(TimebasedState.fromString('PLAYING'), TimebasedState.playing);
      expect(TimebasedState.fromString('Paused'), TimebasedState.paused);
    });

    test('fromString returns none for unknown values', () {
      expect(TimebasedState.fromString('unknown_xyz'), TimebasedState.none);
    });
  });

  group('ReadiumTimebasedState', () {
    test('fromJson normalizes an ended locator with partial location data', () {
      final state = ReadiumTimebasedState.fromJson({
        'state': 'ended',
        'currentLocator': {
          'href': 'last.mp3',
          'type': 'audio/mpeg',
          'locations': {
            'position': 3,
            'fragments': ['t=123.45'],
          },
        },
      });

      expect(state.state, TimebasedState.ended);
      expect(state.currentLocator?.href, 'last.mp3');
      expect(state.currentLocator?.locations?.position, 3);
      expect(state.currentLocator?.locations?.fragments, ['t=123.45']);
      expect(state.currentLocator?.locations?.progression, 1.0);
      expect(state.currentLocator?.locations?.totalProgression, 1.0);
    });
  });

  // ---------------------------------------------------------------------------
  // ReadiumReaderStatus enum
  // ---------------------------------------------------------------------------
  group('ReadiumReaderStatus', () {
    test('fromString returns matching value', () {
      expect(
        ReadiumReaderStatus.optFromString('ready'),
        ReadiumReaderStatus.ready,
      );
      expect(
        ReadiumReaderStatus.optFromString('loading'),
        ReadiumReaderStatus.loading,
      );
      expect(
        ReadiumReaderStatus.optFromString('error'),
        ReadiumReaderStatus.error,
      );
    });

    test('fromString is case-insensitive', () {
      expect(
        ReadiumReaderStatus.optFromString('READY'),
        ReadiumReaderStatus.ready,
      );
    });

    test('fromString returns null for unknown values', () {
      expect(ReadiumReaderStatus.optFromString('unknown_xyz'), isNull);
    });

    test('convenience getters return correct values', () {
      expect(ReadiumReaderStatus.ready.isReady, isTrue);
      expect(ReadiumReaderStatus.ready.isError, isFalse);
      expect(ReadiumReaderStatus.ready.isLoading, isFalse);
      expect(ReadiumReaderStatus.loading.isLoading, isTrue);
      expect(ReadiumReaderStatus.closed.isClosed, isTrue);
      expect(ReadiumReaderStatus.error.isError, isTrue);
      expect(ReadiumReaderStatus.ready.hasReachedEndOfPublication, isFalse);
      expect(
        ReadiumReaderStatus.reachedEndOfPublication.hasReachedEndOfPublication,
        isTrue,
      );

      expect(ReadiumReaderStatus.ready.isLoading, isFalse);
      expect(ReadiumReaderStatus.ready.isError, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // ControlPanelTimebase enum
  // ---------------------------------------------------------------------------
  group('ControlPanelTimebase', () {
    test('fromOptString accepts canonical value', () {
      expect(
        ControlPanelTimebase.fromOptString('wholeBook'),
        ControlPanelTimebase.wholeBook,
      );
    });

    test('fromOptString accepts canonical and snake_case variants', () {
      expect(
        ControlPanelTimebase.fromOptString('whole_book'),
        ControlPanelTimebase.wholeBook,
      );
      expect(
        ControlPanelTimebase.fromOptString('CHAPTER'),
        ControlPanelTimebase.chapter,
      );
    });

    test('fromOptString returns null for unknown values', () {
      expect(ControlPanelTimebase.fromOptString('unknown_xyz'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Preferences fallback behavior
  // ---------------------------------------------------------------------------
  group('Preferences controlPanelTimebase fallback', () {
    test('AudioPreferences.fromJson keeps null when missing', () {
      final prefs = AudioPreferences.fromJson({
        'speed': 1.0,
      });

      expect(prefs.controlPanelTimebase, isNull);
    });

    test('AudioPreferences.fromJson defaults invalid value to chapter', () {
      final prefs = AudioPreferences.fromJson({
        'controlPanelTimebase': 'invalid_value',
      });

      expect(prefs.controlPanelTimebase, ControlPanelTimebase.chapter);
    });

    test('TTSPreferences.fromJson defaults missing value to chapter', () {
      final prefs = TTSPreferences.fromJson({
        'speed': 1.0,
      });

      expect(prefs.controlPanelTimebase, ControlPanelTimebase.chapter);
    });

    test('TTSPreferences.fromJson defaults invalid value to chapter', () {
      final prefs = TTSPreferences.fromJson({
        'controlPanelTimebase': 'invalid_value',
      });

      expect(prefs.controlPanelTimebase, ControlPanelTimebase.chapter);
    });
  });

  // ---------------------------------------------------------------------------
  // TTSVoiceGender enum
  // ---------------------------------------------------------------------------
  group('TTSVoiceGender', () {
    test('fromString returns matching value', () {
      expect(TTSVoiceGender.fromString('male'), TTSVoiceGender.male);
      expect(TTSVoiceGender.fromString('female'), TTSVoiceGender.female);
    });

    test('fromString falls back to unspecified', () {
      expect(TTSVoiceGender.fromString('unknown'), TTSVoiceGender.unspecified);
    });

    test('optFromString returns null for unknown', () {
      expect(TTSVoiceGender.optFromString('unknown'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // TTSVoiceQuality enum
  // ---------------------------------------------------------------------------
  group('TTSVoiceQuality', () {
    test('fromString returns matching value', () {
      expect(TTSVoiceQuality.fromString('high'), TTSVoiceQuality.high);
      expect(TTSVoiceQuality.fromString('lowest'), TTSVoiceQuality.lowest);
    });

    test('fromString falls back to normal', () {
      expect(TTSVoiceQuality.fromString('unknown'), TTSVoiceQuality.normal);
    });

    test('optFromString returns null for unknown', () {
      expect(TTSVoiceQuality.optFromString('unknown'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Publication helpers
  // ---------------------------------------------------------------------------
  group('Publication', () {
    final pub = Publication(
      links: [],
      metadata: Metadata(
        localizedTitle: LocalizedString.fromStrings({'en': 'My Book'}),
      ),
      readingOrder: [Link(href: '/ch1.xhtml', type: 'application/xhtml+xml')],
      tableOfContents: [
        Link(href: '/ch1.xhtml', title: 'Chapter 1'),
        Link(href: '/ch2.xhtml', title: 'Chapter 2'),
      ],
    );

    test('metadata.title returns the title string', () {
      expect(pub.metadata.title, 'My Book');
    });

    test('tocFlattened returns a flat list', () {
      expect(pub.tocFlattened, hasLength(2));
      expect(pub.tocFlattened.first.title, 'Chapter 1');
    });

    test('locatorFromLink returns a locator for a known link', () {
      final link = pub.tableOfContents.first;
      final locator = pub.locatorFromLink(link);
      expect(locator, isNotNull);
      expect(locator!.href, contains('ch1'));
    });
  });

  // ---------------------------------------------------------------------------
  // ImageTapEvent serialisation
  // ---------------------------------------------------------------------------
  group('ImageTapEvent', () {
    test('round-trips a fully-populated iOS-style event through toJson / fromJson', () {
      final event = ImageTapEvent(
        href: 'images/wendy.jpg',
        caption: 'Wendy and the boys',
        rect: const Rect.fromLTWH(10.0, 20.0, 300.0, 200.0),
        pixelWidth: 600,
        pixelHeight: 400,
      );

      final restored = ImageTapEvent.fromJson(event.toJson());
      expect(restored.href, event.href);
      expect(restored.caption, event.caption);
      expect(restored.alt, isNull);
      expect(restored.rect!.left, closeTo(10.0, 1e-9));
      expect(restored.rect!.height, closeTo(200.0, 1e-9));
      expect(restored.pixelWidth, 600);
      expect(restored.pixelHeight, 400);
    });

    test('round-trips a fully-populated web-style event (with alt)', () {
      final event = ImageTapEvent(
        href: 'images/tinker_bell.png',
        alt: 'Tinker Bell',
        rect: const Rect.fromLTWH(0.0, 0.0, 500.0, 350.0),
        pixelWidth: 1000,
        pixelHeight: 700,
      );

      final json = event.toJson();
      final restored = ImageTapEvent.fromJson(json);
      expect(restored.href, event.href);
      expect(restored.alt, 'Tinker Bell');
      expect(restored.caption, isNull);
    });

    test('toJson omits null optional fields', () {
      final event = ImageTapEvent(href: 'images/cover.jpg');
      final json = event.toJson();

      expect(json.containsKey('caption'), isFalse);
      expect(json.containsKey('alt'), isFalse);
      expect(json.containsKey('rect'), isFalse);
      expect(json.containsKey('pixelWidth'), isFalse);
      expect(json.containsKey('pixelHeight'), isFalse);
      expect(json['href'], 'images/cover.jpg');
    });

    test('fromJson tolerates num rect values from native JSON codecs', () {
      // Native method channels decode numbers as int or double; ensure
      // the defensive cast in fromJson handles both.
      final raw = <String, dynamic>{
        'href': 'images/cover.jpg',
        'rect': <String, dynamic>{
          'x': 5, // int, not double
          'y': 10.5, // double
          'width': 200,
          'height': 150,
        },
      };

      final event = ImageTapEvent.fromJson(raw);
      expect(event.rect!.left, 5.0);
      expect(event.rect!.top, closeTo(10.5, 1e-9));
      expect(event.rect!.width, 200.0);
    });

    test('fromJson throws ArgumentError when href is missing', () {
      expect(
        () => ImageTapEvent.fromJson({'alt': 'no href here'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('round-trips through JSON string (the wire format)', () {
      final event = ImageTapEvent(
        href: 'images/neverland.jpg',
        alt: 'Neverland',
      );
      final jsonString = jsonEncode(event.toJson());
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final restored = ImageTapEvent.fromJson(decoded);
      expect(restored.href, event.href);
      expect(restored.alt, event.alt);
    });
  });

  // ---------------------------------------------------------------------------
  // EPUBPreferences — fontSize is a double ratio, no per-platform conversion
  // ---------------------------------------------------------------------------
  group('EPUBPreferences.fontSize', () {
    test('round-trips as double ratio through toJson / fromJson', () {
      const prefs = EPUBPreferences(fontSize: 1.5);
      final json = prefs.toJson();
      expect(json['fontSize'], isA<double>());
      expect(json['fontSize'], closeTo(1.5, 1e-9));
      final restored = EPUBPreferences.fromJson(json);
      expect(restored.fontSize, closeTo(1.5, 1e-9));
    });

    test('null fontSize round-trips as absent', () {
      const prefs = EPUBPreferences();
      final json = prefs.toJson();
      expect(json.containsKey('fontSize'), isFalse);
      final restored = EPUBPreferences.fromJson(json);
      expect(restored.fontSize, isNull);
    });

    test('default ratio (1.0) is preserved', () {
      const prefs = EPUBPreferences(fontSize: 1.0);
      final restored = EPUBPreferences.fromJson(prefs.toJson());
      expect(restored.fontSize, closeTo(1.0, 1e-9));
    });

    test('toJson clamps an unmigrated percentage value to the max ratio', () {
      // A client still passing the old percentage int (90 = "90%") instead of
      // the ratio 0.9 must not reach the native side as 90.0 (→ 9000% on iOS).
      const prefs = EPUBPreferences(fontSize: 90);
      final json = prefs.toJson();
      expect(json['fontSize'], isA<double>());
      expect(json['fontSize'], closeTo(5.0, 1e-9));
    });

    test('toJson clamps a too-small ratio to the min', () {
      const prefs = EPUBPreferences(fontSize: 0.01);
      expect(prefs.toJson()['fontSize'], closeTo(0.1, 1e-9));
    });

    test('toJson leaves an in-range ratio untouched', () {
      const prefs = EPUBPreferences(fontSize: 2.5);
      expect(prefs.toJson()['fontSize'], closeTo(2.5, 1e-9));
    });
  });

  // ---------------------------------------------------------------------------
  // AudioRecoveryPolicy
  // ---------------------------------------------------------------------------
  group('AudioRecoveryPolicy', () {
    test('defaults reproduce prior hardcoded recovery behaviour', () {
      const policy = AudioRecoveryPolicy();
      expect(policy.maxAttempts, 3);
      expect(policy.backoffBaseSeconds, 1.0);
      expect(policy.stallTimeoutSeconds, 20.0);
      expect(policy.connectionTimeoutSeconds, 10.0);
    });

    test('toJson emits a flat map (not nested/JSON-encoded)', () {
      const policy = AudioRecoveryPolicy(
        maxAttempts: 5,
        backoffBaseSeconds: 2.0,
        stallTimeoutSeconds: 15.0,
        connectionTimeoutSeconds: 8.0,
      );
      expect(policy.toJson(), {
        'maxAttempts': 5,
        'backoffBaseSeconds': 2.0,
        'stallTimeoutSeconds': 15.0,
        'connectionTimeoutSeconds': 8.0,
      });
    });

    test('fromJson round-trips toJson', () {
      const policy = AudioRecoveryPolicy(
        maxAttempts: 4,
        backoffBaseSeconds: 1.5,
        stallTimeoutSeconds: 30.0,
        connectionTimeoutSeconds: 12.0,
      );
      final restored = AudioRecoveryPolicy.fromJson(policy.toJson());
      expect(restored, policy);
    });

    test('fromJson falls back to defaults for missing fields', () {
      final policy = AudioRecoveryPolicy.fromJson({});
      expect(policy, const AudioRecoveryPolicy());
    });

    test('copyWith overrides only the given fields', () {
      const policy = AudioRecoveryPolicy();
      final updated = policy.copyWith(stallTimeoutSeconds: 10.0);
      expect(updated.maxAttempts, 3);
      expect(updated.backoffBaseSeconds, 1.0);
      expect(updated.stallTimeoutSeconds, 10.0);
    });

    test('equality is value-based', () {
      expect(const AudioRecoveryPolicy(), const AudioRecoveryPolicy());
      expect(
        const AudioRecoveryPolicy(maxAttempts: 5),
        isNot(const AudioRecoveryPolicy()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Properties serialisation
  // ---------------------------------------------------------------------------
  group('Properties', () {
    test('toJson emits presentation enums as their string names', () {
      final json = Properties(
        orientation: PresentationOrientation.landscape,
        layout: EpubLayout.fixed,
        overflow: PresentationOverflow.paginated,
        spread: PresentationSpread.both,
      ).toJson();

      expect(json['orientation'], 'landscape');
      expect(json['layout'], 'fixed');
      expect(json['overflow'], 'paginated');
      expect(json['spread'], 'both');
    });

    test('toJson output is json-encodable for a fixed-layout resource', () {
      // Regression: raw EpubLayout (and sibling enums) leaked into toJson,
      // so jsonEncode threw for FXL publications (HydratedUnsupportedError).
      final json = Properties(layout: EpubLayout.fixed).toJson();
      expect(() => jsonEncode(json), returnsNormally);
    });

    test('round-trips presentation enums through toJson / fromJson', () {
      final properties = Properties(
        orientation: PresentationOrientation.landscape,
        layout: EpubLayout.fixed,
        overflow: PresentationOverflow.paginated,
        spread: PresentationSpread.both,
      );
      final restored = Properties.fromJson(properties.toJson());

      expect(restored.orientation, PresentationOrientation.landscape);
      expect(restored.layout, EpubLayout.fixed);
      expect(restored.overflow, PresentationOverflow.paginated);
      expect(restored.spread, PresentationSpread.both);
    });
  });
}
