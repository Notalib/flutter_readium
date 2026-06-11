import 'dart:convert';

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
      const e = ReadiumException('something failed');
      expect(e.toString(), contains('something failed'));
    });

    test('fromError wraps arbitrary errors', () {
      final e = ReadiumException.fromError(Exception('boom'));
      expect(e, isA<ReadiumException>());
      expect(e.message, contains('boom'));
    });
  });

  group('OpeningReadiumException', () {
    test('type is preserved', () {
      const e = OpeningReadiumException(
        'not found',
        type: OpeningReadiumExceptionType.notFound,
      );
      expect(e.type, OpeningReadiumExceptionType.notFound);
    });

    test('toString includes type and message', () {
      const e = OpeningReadiumException(
        'msg',
        type: OpeningReadiumExceptionType.forbidden,
      );
      expect(e.toString(), contains('forbidden'));
      expect(e.toString(), contains('msg'));
    });
  });

  group('ReadiumError', () {
    test('equality is based on message and code', () {
      final a = ReadiumError('oops', code: '42');
      final b = ReadiumError('oops', code: '42');
      expect(a, equals(b));
    });

    test('round-trips through toJson / fromJson', () {
      final error = ReadiumError('oops', code: '42', data: 'extra');
      final restored = ReadiumError.fromJson(error.toJson());
      expect(restored.message, 'oops');
      expect(restored.code, '42');
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
}
