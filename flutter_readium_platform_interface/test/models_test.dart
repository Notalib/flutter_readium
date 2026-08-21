import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReaderFontFamily', () {
    test('round-trips static faces through map serialization', () {
      final family = ReaderFontFamily(
        name: 'Atkinson Hyperlegible',
        fallbacks: ['sans-serif'],
        faces: [
          ReaderFontFace(asset: 'assets/fonts/Atkinson-Regular.ttf'),
          ReaderFontFace(
            asset: 'assets/fonts/Atkinson-Italic.ttf',
            style: ReaderFontStyle.italic,
          ),
          ReaderFontFace(
            asset: 'assets/fonts/Atkinson-Bold.ttf',
            weight: 700,
          ),
          ReaderFontFace(
            asset: 'assets/fonts/Atkinson-BoldItalic.ttf',
            style: ReaderFontStyle.italic,
            weight: 700,
          ),
        ],
      );

      final restored = ReaderFontFamily.fromMap(family.toMap());

      expect(restored.name, family.name);
      expect(restored.fallbacks, family.fallbacks);
      expect(
        restored.faces.map((face) => face.toMap()),
        family.faces.map((face) => face.toMap()),
      );
    });

    test('rejects an empty faces list from serialized input', () {
      expect(
        () => ReaderFontFamily.fromMap({
          'name': 'Empty',
          'fallbacks': <String>[],
          'faces': <Map<String, Object>>[],
        }),
        throwsArgumentError,
      );
    });
  });

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

    test('copyWith() with no args preserves all fields', () {
      final locator = Locator(
        href: '/ch.xhtml',
        type: 'application/xhtml+xml',
        title: 'Chapter 1',
        locations: Locations(progression: 0.5),
        text: LocatorText(before: 'a', highlight: 'b', after: 'c'),
      );
      final copied = locator.copyWith();
      expect(copied.href, '/ch.xhtml');
      expect(copied.type, 'application/xhtml+xml');
      expect(copied.title, 'Chapter 1');
      expect(copied.locations?.progression, closeTo(0.5, 1e-6));
      expect(copied.text?.before, 'a');
    });

    test('copyWith() overrides only specified fields', () {
      final locator = Locator(
        href: '/ch.xhtml',
        type: 'application/xhtml+xml',
        title: 'Chapter 1',
      );
      final updated = locator.copyWith(title: 'Updated');
      expect(updated.href, '/ch.xhtml');
      expect(updated.title, 'Updated');
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

    test('copyWith() with no args preserves all fields', () {
      const prefs = EPUBPreferences(
        preventMOColumnBreaks: true,
        spread: 'both',
      );
      final copied = prefs.copyWith();
      expect(copied.preventMOColumnBreaks, isTrue);
      expect(copied.spread, 'both');
    });

    test('copyWith() overrides only specified fields', () {
      const prefs = EPUBPreferences(
        preventMOColumnBreaks: false,
        spread: 'both',
      );
      final updated = prefs.copyWith(preventMOColumnBreaks: true);
      expect(updated.preventMOColumnBreaks, isTrue);
      expect(updated.spread, 'both');
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

    test('copyWith() with no args preserves all fields', () {
      const prefs = PDFPreferences(
        layout: PDFLayout.scrollVertical,
        readingProgression: PDFReadingProgression.rtl,
        pageSpacing: 12.5,
        fit: PDFFit.page,
      );
      final copied = prefs.copyWith();
      expect(copied.layout, PDFLayout.scrollVertical);
      expect(copied.readingProgression, PDFReadingProgression.rtl);
      expect(copied.pageSpacing, 12.5);
      expect(copied.fit, PDFFit.page);
    });

    test('copyWith() overrides only specified fields', () {
      const prefs = PDFPreferences(
        layout: PDFLayout.scrollVertical,
        pageSpacing: 12.5,
      );
      final updated = prefs.copyWith(pageSpacing: 20.0);
      expect(updated.layout, PDFLayout.scrollVertical);
      expect(updated.pageSpacing, 20.0);
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

  // ---------------------------------------------------------------------------
  // ExternalPlaybackCommandAction enum
  // ---------------------------------------------------------------------------
  group('ReadiumExternalPlaybackCommand', () {
    test('parses every action case-insensitively', () {
      for (final action in ExternalPlaybackCommandAction.values) {
        expect(
          ExternalPlaybackCommandAction.fromString(action.name.toUpperCase()),
          action,
        );
      }
    });

    test('round-trips through toJson / fromJson', () {
      const command = ReadiumExternalPlaybackCommand(
        action: ExternalPlaybackCommandAction.seekTo,
        position: Duration(seconds: 42),
      );

      final restored = ReadiumExternalPlaybackCommand.fromJson(command.toJson());

      expect(restored.action, ExternalPlaybackCommandAction.seekTo);
      expect(restored.position, const Duration(seconds: 42));
    });

    test('unknown action falls back to unknown', () {
      final command = ReadiumExternalPlaybackCommand.fromJson({
        'action': 'definitelyNotACommand',
      });

      expect(command.action, ExternalPlaybackCommandAction.unknown);
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

    test('copyWith() with no args preserves all fields', () {
      const policy = AudioRecoveryPolicy(
        maxAttempts: 5,
        backoffBaseSeconds: 2.0,
        stallTimeoutSeconds: 30.0,
        connectionTimeoutSeconds: 10.0,
      );
      final copied = policy.copyWith();
      expect(copied.maxAttempts, 5);
      expect(copied.backoffBaseSeconds, 2.0);
      expect(copied.stallTimeoutSeconds, 30.0);
      expect(copied.connectionTimeoutSeconds, 10.0);
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
  // ReaderTTSVoice copyWith
  // ---------------------------------------------------------------------------
  group('ReaderTTSVoice', () {
    test('copyWith() with no args preserves all fields', () {
      final voice = ReaderTTSVoice(
        identifier: 'voice1',
        name: 'Test Voice',
        language: 'en-US',
        networkRequired: false,
        gender: TTSVoiceGender.unspecified,
        quality: TTSVoiceQuality.normal,
        active: true,
      );
      final copied = voice.copyWith();
      expect(copied.identifier, 'voice1');
      expect(copied.name, 'Test Voice');
      expect(copied.language, 'en-US');
      expect(copied.networkRequired, isFalse);
    });

    test('copyWith() overrides only specified fields', () {
      final voice = ReaderTTSVoice(
        identifier: 'voice1',
        name: 'Test Voice',
        language: 'en-US',
        networkRequired: false,
        gender: TTSVoiceGender.unspecified,
        quality: TTSVoiceQuality.normal,
        active: true,
      );
      final updated = voice.copyWith(name: 'Updated Voice');
      expect(updated.identifier, 'voice1');
      expect(updated.name, 'Updated Voice');
    });

    test('equality is value-based', () {
      final a = ReaderTTSVoice(
        identifier: 'v1',
        name: 'A',
        language: 'en',
        networkRequired: false,
        gender: TTSVoiceGender.unspecified,
        quality: TTSVoiceQuality.normal,
        active: true,
      );
      final b = ReaderTTSVoice(
        identifier: 'v1',
        name: 'A',
        language: 'en',
        networkRequired: false,
        gender: TTSVoiceGender.unspecified,
        quality: TTSVoiceQuality.normal,
        active: true,
      );
      expect(a, equals(b));

      final c = ReaderTTSVoice(
        identifier: 'v1',
        name: 'B',
        language: 'en',
        networkRequired: false,
        gender: TTSVoiceGender.unspecified,
        quality: TTSVoiceQuality.normal,
        active: true,
      );
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // ReaderDecoration copyWith
  // ---------------------------------------------------------------------------
  group('ReaderDecoration', () {
    test('copyWith() with no args preserves all fields', () {
      final decoration = ReaderDecoration(
        id: 'deco1',
        locator: const Locator(href: '/ch.xhtml', type: 'application/xhtml+xml'),
        style: const ReaderDecorationStyle(style: DecorationStyle.highlight),
      );
      final copied = decoration.copyWith();
      expect(copied.id, 'deco1');
      expect(copied.locator.href, '/ch.xhtml');
    });

    test('copyWith() overrides only specified fields', () {
      final decoration = ReaderDecoration(
        id: 'deco1',
        locator: const Locator(href: '/ch.xhtml', type: 'application/xhtml+xml'),
        style: const ReaderDecorationStyle(style: DecorationStyle.highlight),
      );
      final updated = decoration.copyWith(id: 'deco2');
      expect(updated.id, 'deco2');
      expect(updated.locator.href, '/ch.xhtml');
    });
  });

  // ---------------------------------------------------------------------------
  // ReaderDecorationStyle copyWith
  // ---------------------------------------------------------------------------
  group('ReaderDecorationStyle', () {
    test('copyWith() with no args preserves all fields', () {
      final style = ReaderDecorationStyle(
        style: DecorationStyle.highlight,
        tint: const Color(0xFFFF0000),
      );
      final copied = style.copyWith();
      expect(copied.style, DecorationStyle.highlight);
      expect(copied.tint, const Color(0xFFFF0000));
    });

    test('copyWith() overrides only specified fields', () {
      final style = ReaderDecorationStyle(
        style: DecorationStyle.highlight,
        tint: const Color(0xFFFF0000),
      );
      final updated = style.copyWith(tint: const Color(0xFF00FF00));
      expect(updated.style, DecorationStyle.highlight);
      expect(updated.tint, const Color(0xFF00FF00));
    });
  });

  // ---------------------------------------------------------------------------
  // ReadiumTimebasedState copyWith
  // ---------------------------------------------------------------------------
  group('ReadiumTimebasedState', () {
    test('copyWith() with no args preserves all fields', () {
      final state = ReadiumTimebasedState(
        state: TimebasedState.playing,
        currentLocator: const Locator(href: '/ch.xhtml', type: 'application/xhtml+xml'),
      );
      final copied = state.copyWith();
      expect(copied.state, TimebasedState.playing);
      expect(copied.currentLocator?.href, '/ch.xhtml');
    });

    test('copyWith() overrides only specified fields', () {
      final state = ReadiumTimebasedState(
        state: TimebasedState.playing,
      );
      final updated = state.copyWith(state: TimebasedState.paused);
      expect(updated.state, TimebasedState.paused);
    });
  });

  // ---------------------------------------------------------------------------
  // Facet copyWith
  // ---------------------------------------------------------------------------
  group('Facet', () {
    test('copyWith() with no args preserves all fields', () {
      final facet = Facet(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
        links: [const Link(href: '/link1.xhtml')],
      );
      final copied = facet.copyWith();
      expect(copied.metadata, facet.metadata);
      expect(copied.links, facet.links);
    });

    test('copyWith() overrides only specified fields', () {
      final facet = Facet(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
        links: [const Link(href: '/link1.xhtml')],
      );
      final updated = facet.copyWith(links: [const Link(href: '/link2.xhtml')]);
      expect(updated.links.first.href, '/link2.xhtml');
    });

    test('equality is value-based', () {
      final a = Facet(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
        links: [const Link(href: '/l1.xhtml')],
      );
      final b = Facet(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
        links: [const Link(href: '/l1.xhtml')],
      );
      expect(a, equals(b));

      final c = Facet(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
        links: [const Link(href: '/l2.xhtml')],
      );
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // OpdsPublication copyWith
  // ---------------------------------------------------------------------------
  group('OpdsPublication', () {
    test('copyWith() with no args preserves all fields', () {
      final pub = OpdsPublication(
        const OpdsMetadata(localizedTitle: LocalizedString()),
        [const Link(href: '/link1.xhtml')],
      );
      final copied = pub.copyWith();
      expect(copied.metadata, pub.metadata);
      expect(copied.links, pub.links);
    });

    test('copyWith() overrides only specified fields', () {
      final pub = OpdsPublication(
        const OpdsMetadata(localizedTitle: LocalizedString()),
        [const Link(href: '/link1.xhtml')],
      );
      final updated = pub.copyWith(links: [const Link(href: '/link2.xhtml')]);
      expect(updated.links.first.href, '/link2.xhtml');
    });
  });

  // ---------------------------------------------------------------------------
  // Properties copyWith
  // ---------------------------------------------------------------------------
  group('Properties', () {
    test('copyWith() with no args preserves all fields', () {
      final props = Properties(
        orientation: PresentationOrientation.landscape,
        layout: EpubLayout.fixed,
      );
      final copied = props.copyWith();
      expect(copied.orientation, PresentationOrientation.landscape);
      expect(copied.layout, EpubLayout.fixed);
    });

    test('copyWith() overrides only specified fields', () {
      final props = Properties(orientation: PresentationOrientation.landscape);
      final updated = props.copyWith(layout: EpubLayout.reflowable);
      expect(updated.orientation, PresentationOrientation.landscape);
      expect(updated.layout, EpubLayout.reflowable);
    });
  });

  // ---------------------------------------------------------------------------
  // Chapter copyWith
  // ---------------------------------------------------------------------------
  group('Chapter', () {
    test('copyWith() with no args preserves all fields', () {
      final chapter = Chapter(position: 1.0);
      final copied = chapter.copyWith();
      expect(copied.position, 1.0);
    });

    test('copyWith() overrides only specified fields', () {
      final chapter = Chapter(position: 1.0);
      final updated = chapter.copyWith(position: 2.0);
      expect(updated.position, 2.0);
    });

    test('equality is value-based', () {
      final a = Chapter(position: 1.0);
      final b = Chapter(position: 1.0);
      expect(a, equals(b));

      final c = Chapter(position: 2.0);
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // Season copyWith
  // ---------------------------------------------------------------------------
  group('Season', () {
    test('copyWith() with no args preserves all fields', () {
      final season = Season(position: 1.0);
      final copied = season.copyWith();
      expect(copied.position, 1.0);
    });

    test('copyWith() overrides only specified fields', () {
      final season = Season(position: 1.0);
      final updated = season.copyWith(position: 2.0);
      expect(updated.position, 2.0);
    });

    test('equality is value-based', () {
      final a = Season(position: 1.0);
      final b = Season(position: 1.0);
      expect(a, equals(b));

      final c = Season(position: 2.0);
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // Episode copyWith
  // ---------------------------------------------------------------------------
  group('Episode', () {
    test('copyWith() with no args preserves all fields', () {
      final episode = Episode(position: 1.0);
      final copied = episode.copyWith();
      expect(copied.position, 1.0);
    });

    test('copyWith() overrides only specified fields', () {
      final episode = Episode(position: 1.0);
      final updated = episode.copyWith(position: 2.0);
      expect(updated.position, 2.0);
    });

    test('equality is value-based', () {
      final a = Episode(position: 1.0);
      final b = Episode(position: 1.0);
      expect(a, equals(b));

      final c = Episode(position: 2.0);
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // Issue copyWith
  // ---------------------------------------------------------------------------
  group('Issue', () {
    test('copyWith() with no args preserves all fields', () {
      final issue = Issue(position: 1.0);
      final copied = issue.copyWith();
      expect(copied.position, 1.0);
    });

    test('copyWith() overrides only specified fields', () {
      final issue = Issue(position: 1.0);
      final updated = issue.copyWith(position: 2.0);
      expect(updated.position, 2.0);
    });

    test('equality is value-based', () {
      final a = Issue(position: 1.0);
      final b = Issue(position: 1.0);
      expect(a, equals(b));

      final c = Issue(position: 2.0);
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // Periodical copyWith
  // ---------------------------------------------------------------------------
  group('Periodical', () {
    test('copyWith() with no args preserves all fields', () {
      final periodical = Periodical(localizedName: LocalizedString());
      final copied = periodical.copyWith();
      expect(copied.localizedName, isNotNull);
    });

    test('copyWith() overrides only specified fields', () {
      final periodical = Periodical(localizedName: LocalizedString());
      final updated = periodical.copyWith(identifier: 'id1');
      expect(updated.identifier, 'id1');
    });

    test('equality is value-based', () {
      final a = Periodical(localizedName: LocalizedString());
      final b = Periodical(localizedName: LocalizedString());
      expect(a, equals(b));

      final c = Periodical(localizedName: LocalizedString(), identifier: 'id1');
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // Collection copyWith
  // ---------------------------------------------------------------------------
  group('Collection', () {
    test('copyWith() with no args preserves all fields', () {
      final collection = Collection(localizedName: LocalizedString());
      final copied = collection.copyWith();
      expect(copied.localizedName, isNotNull);
    });

    test('copyWith() overrides only specified fields', () {
      final collection = Collection(localizedName: LocalizedString());
      final updated = collection.copyWith(identifier: 'id1');
      expect(updated.identifier, 'id1');
    });

    test('equality is value-based', () {
      final a = Collection(localizedName: LocalizedString());
      final b = Collection(localizedName: LocalizedString());
      expect(a, equals(b));

      final c = Collection(localizedName: LocalizedString(), identifier: 'id1');
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // Contributor copyWith
  // ---------------------------------------------------------------------------
  group('Contributor', () {
    test('copyWith() with no args preserves all fields', () {
      final contributor = Contributor(localizedName: LocalizedString());
      final copied = contributor.copyWith();
      expect(copied.localizedName, isNotNull);
    });

    test('copyWith() overrides only specified fields', () {
      final contributor = Contributor(localizedName: LocalizedString());
      final updated = contributor.copyWith(identifier: 'id1');
      expect(updated.identifier, 'id1');
    });

    test('equality is value-based', () {
      final a = Contributor(localizedName: LocalizedString());
      final b = Contributor(localizedName: LocalizedString());
      expect(a, equals(b));

      final c = Contributor(localizedName: LocalizedString(), identifier: 'id1');
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // OpdsMetadata copyWith
  // ---------------------------------------------------------------------------
  group('OpdsMetadata', () {
    test('copyWith() with no args preserves all fields', () {
      final metadata = OpdsMetadata(
        localizedTitle: LocalizedString(),
      );
      final copied = metadata.copyWith();
      expect(copied.localizedTitle, metadata.localizedTitle);
    });

    test('copyWith() overrides only specified fields', () {
      final metadata = OpdsMetadata(
        localizedTitle: LocalizedString(),
      );
      final updated = metadata.copyWith(identifier: 'id1');
      expect(updated.identifier, 'id1');
    });

    test('equality is value-based', () {
      final a = OpdsMetadata(localizedTitle: LocalizedString());
      final b = OpdsMetadata(localizedTitle: LocalizedString());
      expect(a, equals(b));

      final c = OpdsMetadata(localizedTitle: LocalizedString(), identifier: 'id1');
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // Feed copyWith
  // ---------------------------------------------------------------------------
  group('Feed', () {
    test('copyWith() with no args preserves all fields', () {
      final feed = Feed(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
      );
      final copied = feed.copyWith();
      expect(copied.metadata, feed.metadata);
    });

    test('copyWith() overrides only specified fields', () {
      final feed = Feed(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
      );
      final updated = feed.copyWith(links: [const Link(href: '/link1.xhtml')]);
      expect(updated.links, isNotEmpty);
    });

    test('equality is value-based', () {
      final a = Feed(metadata: const OpdsMetadata(localizedTitle: LocalizedString()));
      final b = Feed(metadata: const OpdsMetadata(localizedTitle: LocalizedString()));
      expect(a, equals(b));

      final c = Feed(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
        links: [const Link(href: '/l1.xhtml')],
      );
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // Group copyWith
  // ---------------------------------------------------------------------------
  group('Group', () {
    test('copyWith() with no args preserves all fields', () {
      final group = Group(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
        links: [const Link(href: '/link1.xhtml')],
      );
      final copied = group.copyWith();
      expect(copied.metadata, group.metadata);
      expect(copied.links, group.links);
    });

    test('copyWith() overrides only specified fields', () {
      final group = Group(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
        links: [const Link(href: '/link1.xhtml')],
      );
      final updated = group.copyWith(links: [const Link(href: '/link2.xhtml')]);
      expect(updated.links.first.href, '/link2.xhtml');
    });

    test('equality is value-based', () {
      final a = Group(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
        links: [const Link(href: '/l1.xhtml')],
      );
      final b = Group(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
        links: [const Link(href: '/l1.xhtml')],
      );
      expect(a, equals(b));

      final c = Group(
        metadata: const OpdsMetadata(localizedTitle: LocalizedString()),
        links: [const Link(href: '/l2.xhtml')],
      );
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // OpdsAuthentication copyWith
  // ---------------------------------------------------------------------------
  group('OpdsAuthentication', () {
    test('copyWith() with no args preserves all fields', () {
      final auth = OpdsAuthentication(
        type: 'http://opds-spec.org/auth/schemes/open',
        id: 'auth1',
      );
      final copied = auth.copyWith();
      expect(copied.type, 'http://opds-spec.org/auth/schemes/open');
      expect(copied.id, 'auth1');
    });

    test('copyWith() overrides only specified fields', () {
      final auth = OpdsAuthentication(
        type: 'http://opds-spec.org/auth/schemes/open',
        id: 'auth1',
      );
      final updated = auth.copyWith(id: 'auth2');
      expect(updated.type, 'http://opds-spec.org/auth/schemes/open');
      expect(updated.id, 'auth2');
    });

    test('equality is value-based', () {
      final a = OpdsAuthentication(type: 't1', id: 'i1');
      final b = OpdsAuthentication(type: 't1', id: 'i1');
      expect(a, equals(b));

      final c = OpdsAuthentication(type: 't1', id: 'i2');
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // OpdsAuthenticationFlow copyWith
  // ---------------------------------------------------------------------------
  group('OpdsAuthenticationFlow', () {
    test('copyWith() with no args preserves all fields', () {
      final flow = OpdsAuthenticationFlow(
        type: 'http://opds-spec.org/auth/schemes/open',
      );
      final copied = flow.copyWith();
      expect(copied.type, 'http://opds-spec.org/auth/schemes/open');
    });

    test('copyWith() overrides only specified fields', () {
      final flow = OpdsAuthenticationFlow(
        type: 'http://opds-spec.org/auth/schemes/open',
      );
      final updated = flow.copyWith(links: [const Link(href: '/link1.xhtml')]);
      expect(updated.links, isNotEmpty);
    });

    test('equality is value-based', () {
      final a = OpdsAuthenticationFlow(type: 't1');
      final b = OpdsAuthenticationFlow(type: 't1');
      expect(a, equals(b));

      final c = OpdsAuthenticationFlow(type: 't2');
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // Announcement copyWith
  // ---------------------------------------------------------------------------
  group('Announcement', () {
    test('copyWith() with no args preserves all fields', () {
      final announcement = Announcement(
        id: 'announce1',
        content: 'Test Announcement',
      );
      final copied = announcement.copyWith();
      expect(copied.id, 'announce1');
      expect(copied.content, 'Test Announcement');
    });

    test('copyWith() overrides only specified fields', () {
      final announcement = Announcement(
        id: 'announce1',
        content: 'Original',
      );
      final updated = announcement.copyWith(content: 'Updated');
      expect(updated.id, 'announce1');
      expect(updated.content, 'Updated');
    });

    test('equality is value-based', () {
      final a = Announcement(id: 'a1', content: 'C');
      final b = Announcement(id: 'a1', content: 'C');
      expect(a, equals(b));

      final c = Announcement(id: 'a1', content: 'D');
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // FeatureFlags copyWith
  // ---------------------------------------------------------------------------
  group('FeatureFlags', () {
    test('copyWith() with no args preserves all fields', () {
      final flags = FeatureFlags(
        enabled: ['feature1'],
        disabled: ['feature2'],
      );
      final copied = flags.copyWith();
      expect(copied.enabled, ['feature1']);
      expect(copied.disabled, ['feature2']);
    });

    test('copyWith() overrides only specified fields', () {
      final flags = FeatureFlags(
        enabled: ['feature1'],
        disabled: ['feature2'],
      );
      final updated = flags.copyWith(enabled: ['feature3']);
      expect(updated.enabled, ['feature3']);
    });

    test('equality is value-based', () {
      final a = FeatureFlags(enabled: ['f1'], disabled: ['f2']);
      final b = FeatureFlags(enabled: ['f1'], disabled: ['f2']);
      expect(a, equals(b));

      final c = FeatureFlags(enabled: ['f3'], disabled: ['f2']);
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // InputField copyWith
  // ---------------------------------------------------------------------------
  group('InputField', () {
    test('copyWith() with no args preserves all fields', () {
      final field = InputField(
        keyboard: KeyboardType.defaultType,
        maximumLength: 100,
      );
      final copied = field.copyWith();
      expect(copied.keyboard, KeyboardType.defaultType);
      expect(copied.maximumLength, 100);
    });

    test('copyWith() overrides only specified fields', () {
      final field = InputField(
        keyboard: KeyboardType.defaultType,
        maximumLength: 100,
      );
      final updated = field.copyWith(maximumLength: 200);
      expect(updated.keyboard, KeyboardType.defaultType);
      expect(updated.maximumLength, 200);
    });

    test('equality is value-based', () {
      final a = InputField(keyboard: KeyboardType.defaultType, maximumLength: 100);
      final b = InputField(keyboard: KeyboardType.defaultType, maximumLength: 100);
      expect(a, equals(b));

      final c = InputField(keyboard: KeyboardType.defaultType, maximumLength: 200);
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // LoginInputField copyWith
  // ---------------------------------------------------------------------------
  group('LoginInputField', () {
    test('copyWith() with no args preserves all fields', () {
      final loginField = LoginInputField(
        barcodeFormat: 'qr-code',
      );
      final copied = loginField.copyWith();
      expect(copied.barcodeFormat, 'qr-code');
    });

    test('copyWith() overrides only specified fields', () {
      final loginField = LoginInputField(
        barcodeFormat: 'qr-code',
      );
      final updated = loginField.copyWith(barcodeFormat: 'barcode');
      expect(updated.barcodeFormat, 'barcode');
    });

    test('equality is value-based', () {
      final a = LoginInputField(barcodeFormat: 'qr-code');
      final b = LoginInputField(barcodeFormat: 'qr-code');
      expect(a, equals(b));

      final c = LoginInputField(barcodeFormat: 'barcode');
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // InputData copyWith
  // ---------------------------------------------------------------------------
  group('InputData', () {
    test('copyWith() with no args preserves all fields', () {
      final inputData = InputData(
        login: const LoginInputField(),
        password: const InputField(),
      );
      final copied = inputData.copyWith();
      expect(copied.login, const LoginInputField());
      expect(copied.password, const InputField());
    });

    test('copyWith() overrides only specified fields', () {
      final inputData = InputData(
        login: const LoginInputField(),
        password: const InputField(),
      );
      final updated = inputData.copyWith(password: const InputField(keyboard: KeyboardType.numPad));
      expect(updated.password.keyboard, KeyboardType.numPad);
    });

    test('equality is value-based', () {
      final a = InputData();
      final b = InputData();
      expect(a, equals(b));

      final c = InputData(password: const InputField(keyboard: KeyboardType.numPad));
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // PublicKeyData copyWith
  // ---------------------------------------------------------------------------
  group('PublicKeyData', () {
    test('copyWith() with no args preserves all fields', () {
      final publicKey = PublicKeyData(
        type: 'RSA',
        value: 'base64-encoded-key',
      );
      final copied = publicKey.copyWith();
      expect(copied.type, 'RSA');
      expect(copied.value, 'base64-encoded-key');
    });

    test('copyWith() overrides only specified fields', () {
      final publicKey = PublicKeyData(
        type: 'RSA',
        value: 'base64-encoded-key',
      );
      final updated = publicKey.copyWith(value: 'new-key');
      expect(updated.type, 'RSA');
      expect(updated.value, 'new-key');
    });

    test('equality is value-based', () {
      final a = PublicKeyData(type: 'RSA', value: 'key1');
      final b = PublicKeyData(type: 'RSA', value: 'key1');
      expect(a, equals(b));

      final c = PublicKeyData(type: 'RSA', value: 'key2');
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // WebColor copyWith
  // ---------------------------------------------------------------------------
  group('WebColor', () {
    test('copyWith() with no args preserves all fields', () {
      final color = WebColor(
        primary: '#FF0000',
        secondary: '#00FF00',
      );
      final copied = color.copyWith();
      expect(copied.primary, '#FF0000');
      expect(copied.secondary, '#00FF00');
    });

    test('copyWith() overrides only specified fields', () {
      final color = WebColor(
        primary: '#FF0000',
        secondary: '#00FF00',
      );
      final updated = color.copyWith(primary: '#0000FF');
      expect(updated.primary, '#0000FF');
      expect(updated.secondary, '#00FF00');
    });

    test('equality is value-based', () {
      final a = WebColor(primary: '#FF0000', secondary: '#00FF00');
      final b = WebColor(primary: '#FF0000', secondary: '#00FF00');
      expect(a, equals(b));

      final c = WebColor(primary: '#0000FF', secondary: '#00FF00');
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // LocatorCollection copyWith
  // ---------------------------------------------------------------------------
  group('LocatorCollection', () {
    test('copyWith() with no args preserves all fields', () {
      final collection = LocatorCollection(
        metadata: const LocatorCollectionMetadata(),
      );
      final copied = collection.copyWith();
      expect(copied.metadata, const LocatorCollectionMetadata());
    });

    test('copyWith() overrides only specified fields', () {
      final collection = LocatorCollection(
        metadata: const LocatorCollectionMetadata(),
      );
      final updated = collection.copyWith(links: [const Link(href: '/link1.xhtml')]);
      expect(updated.links, isNotEmpty);
    });

    test('equality is value-based', () {
      final a = LocatorCollection();
      final b = LocatorCollection();
      expect(a, equals(b));

      final c = LocatorCollection(links: [const Link(href: '/l1.xhtml')]);
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // LocatorCollectionMetadata copyWith
  // ---------------------------------------------------------------------------
  group('LocatorCollectionMetadata', () {
    test('copyWith() with no args preserves all fields', () {
      final metadata = LocatorCollectionMetadata(
        localizedTitle: LocalizedString(),
      );
      final copied = metadata.copyWith();
      expect(copied.localizedTitle, isNotNull);
    });

    test('copyWith() overrides only specified fields', () {
      final metadata = LocatorCollectionMetadata(
        localizedTitle: LocalizedString(),
      );
      final updated = metadata.copyWith(numberOfItems: 10);
      expect(updated.numberOfItems, 10);
    });

    test('equality is value-based', () {
      final a = LocatorCollectionMetadata(localizedTitle: LocalizedString());
      final b = LocatorCollectionMetadata(localizedTitle: LocalizedString());
      expect(a, equals(b));

      final c = LocatorCollectionMetadata(localizedTitle: LocalizedString(), numberOfItems: 10);
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // LocalizedString copyWith
  // ---------------------------------------------------------------------------
  group('LocalizedString', () {
    test('copyWith() with no args preserves all fields', () {
      final str = LocalizedString(
        translations: {'en': Translation('Hello')},
      );
      final copied = str.copyWith();
      expect(copied.translations, isNotNull);
    });

    test('copyWith() overrides only specified fields', () {
      final str = LocalizedString(
        translations: {'en': Translation('Original')},
      );
      final updated = str.copyWith(translations: {'en': Translation('Updated')});
      expect(updated.translations, isNotNull);
    });

    test('equality is value-based', () {
      final a = LocalizedString(translations: {'en': Translation('Hello')});
      final b = LocalizedString(translations: {'en': Translation('Hello')});
      expect(a, equals(b));

      final c = LocalizedString(translations: {'en': Translation('Hi')});
      expect(a, isNot(equals(c)));
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
