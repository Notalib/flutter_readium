import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

// Ground-truth fixtures: real Lastmark locators stored under the old
// WebPubAudio-shaped reading order (xhtml hrefs with a media-overlay behind
// them), now resolved against a republished audio-only reading order.
final _fixture26786 = {
  'href': '/26786-0029-generic.xhtml',
  'type': 'audio/mpeg',
  'title': '25',
  'locations': {
    'cssSelector': '#hix00029',
    'fragments': ['t=732.3'],
    'position': 29,
    'progression': 0.9332,
    'totalProgression': 0.4252,
  },
  'x-timestamp': '2026-05-11T14:08:00+00:00',
  'x-type': 'Lastmark',
};

final _fixture27651 = {
  'href': '/27651-0004-generic.xhtml',
  'type': 'audio/mpeg',
  'title': 'Section',
  'locations': {
    'cssSelector': '#text_0029',
    'fragments': ['t=46.8'],
    'position': 4,
    'progression': 0.0631,
    'totalProgression': 0.0036,
  },
  'x-timestamp': '2025-09-15T11:43:39+00:00',
  'x-type': 'Lastmark',
};

final _fixture23308 = {
  'href': '23308-0002-generic.xhtml',
  'type': 'application/xhtml+xml',
  'title': 'Lydbokavtalen',
  'locations': {
    'cssSelector': '#dtb4',
    'fragments': ['t=18.078651722'],
    'position': 2,
    'progression': 0.2949,
    'totalProgression': 0.0003,
  },
  'x-timestamp': '2026-05-28T16:59:29+00:00',
  'x-type': 'Lastmark',
};

Publication _publicationWithReadingOrder(List<Link> readingOrder) => Publication(
  metadata: Metadata(localizedTitle: LocalizedString.fromStrings({'en': 'Test Book'})),
  readingOrder: readingOrder,
);

void main() {
  group('Publication.resolveLocator', () {
    test('href still present returns the locator unchanged', () {
      final link = Link(href: '/ch1.xhtml', type: 'application/xhtml+xml');
      final pub = _publicationWithReadingOrder([link]);
      final locator = Locator(
        href: '/ch1.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(position: 1),
      );

      expect(pub.resolveLocator(locator), same(locator));
    });

    test('href absent, totalProgression usable, durations present resolves via duration', () {
      final readingOrder = [
        Link(href: '/26786-0001.mp3', type: 'audio/mpeg', duration: 100),
        Link(href: '/26786-0002.mp3', type: 'audio/mpeg', duration: 100),
        Link(href: '/26786-0003.mp3', type: 'audio/mpeg', duration: 100),
      ];
      final pub = _publicationWithReadingOrder(readingOrder);
      final locator = Locator.fromJson(_fixture26786)!;

      final resolved = pub.resolveLocator(locator);

      expect(resolved, isNotNull);
      expect(resolved!.href, '/26786-0002.mp3');
      expect(resolved.type, 'audio/mpeg');
      expect(resolved.locations?.position, 2);
      expect(resolved.locations?.progression, closeTo(0.2756, 1e-3));
      expect(resolved.locations?.totalProgression, closeTo(0.4252, 1e-6));
    });

    test('href absent, durations absent falls through to position without crashing', () {
      final readingOrder = [
        Link(href: '/27651-0001.mp3', type: 'audio/mpeg'),
        Link(href: '/27651-0002.mp3', type: 'audio/mpeg', duration: 50),
        Link(href: '/27651-0003.mp3', type: 'audio/mpeg'),
        Link(href: '/27651-0004.mp3', type: 'audio/mpeg', duration: 40),
      ];
      final pub = _publicationWithReadingOrder(readingOrder);
      final locator = Locator.fromJson(_fixture27651)!;

      final resolved = pub.resolveLocator(locator);

      expect(resolved, isNotNull);
      expect(resolved!.href, '/27651-0004.mp3');
      expect(resolved.locations?.position, 4);
      expect(resolved.locations?.progression, isNull);
    });

    test('position beyond readingOrder length returns null instead of throwing', () {
      final readingOrder = [
        Link(href: '/a.mp3', type: 'audio/mpeg'),
        Link(href: '/b.mp3', type: 'audio/mpeg'),
      ];
      final pub = _publicationWithReadingOrder(readingOrder);
      final locator = Locator(
        href: '/missing.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(position: 5),
      );

      expect(() => pub.resolveLocator(locator), returnsNormally);
      expect(pub.resolveLocator(locator), isNull);
    });

    test('totalProgression == 0 with position > 1 prefers position over duration', () {
      final readingOrder = [
        Link(href: '/a.mp3', type: 'audio/mpeg', duration: 10),
        Link(href: '/b.mp3', type: 'audio/mpeg', duration: 10),
        Link(href: '/c.mp3', type: 'audio/mpeg', duration: 10),
      ];
      final pub = _publicationWithReadingOrder(readingOrder);
      final locator = Locator(
        href: '/missing.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(position: 3, totalProgression: 0),
      );

      final resolved = pub.resolveLocator(locator);

      expect(resolved, isNotNull);
      expect(resolved!.href, '/c.mp3');
      expect(resolved.locations?.position, 3);
      expect(resolved.locations?.progression, isNull);
    });

    test('totalProgression == 1.0 lands in the last link, not out of range', () {
      final readingOrder = [
        Link(href: '/a.mp3', type: 'audio/mpeg', duration: 10),
        Link(href: '/b.mp3', type: 'audio/mpeg', duration: 20),
      ];
      final pub = _publicationWithReadingOrder(readingOrder);
      final locator = Locator(
        href: '/missing.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(totalProgression: 1),
      );

      final resolved = pub.resolveLocator(locator);

      expect(resolved, isNotNull);
      expect(resolved!.href, '/b.mp3');
      expect(resolved.locations?.position, 2);
      expect(resolved.locations?.progression, closeTo(1.0, 1e-9));
    });

    test('empty reading order returns null', () {
      final pub = _publicationWithReadingOrder([]);
      final locator = Locator(
        href: '/missing.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(position: 1, totalProgression: 0.5),
      );

      expect(pub.resolveLocator(locator), isNull);
    });

    test('resolved locator drops stale cssSelector/fragments and updates type', () {
      final readingOrder = [
        Link(href: '/23308-0001.mp3', type: 'audio/mpeg', duration: 10),
        Link(href: '/23308-0002.mp3', type: 'audio/mpeg', duration: 10),
      ];
      final pub = _publicationWithReadingOrder(readingOrder);
      final locator = Locator.fromJson(_fixture23308)!;
      // Sanity: the fixture really does carry stale HTML-fragment locations.
      expect(locator.locations?.cssSelector, isNotNull);
      expect(locator.type, 'application/xhtml+xml');

      final resolved = pub.resolveLocator(locator);

      expect(resolved, isNotNull);
      expect(resolved!.type, 'audio/mpeg');
      expect(resolved.locations?.cssSelector, isNull);
      expect(resolved.locations?.fragments, isEmpty);
    });
  });
}
