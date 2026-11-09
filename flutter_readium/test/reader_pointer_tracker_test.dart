import 'package:flutter/services.dart';
import 'package:flutter_readium/reader_channel.dart';
import 'package:flutter_readium/reader_pointer_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

const _tapSlop = 18.0;
const _panSlop = 36.0;
const _width = 400.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> events;
  late ReaderPointerTracker tracker;

  setUp(() {
    events = [];
    tracker = ReaderPointerTracker(
      onDeliberateDrag: () => events.add('hide'),
      onUserNavigation: () => events.add('manual'),
      onEdgeTap: () => events.add('edge'),
      onCenterTap: () => events.add('center'),
    );
  });

  void down(int pointer, Offset at) => tracker.down(pointer, at, tapSlop: _tapSlop, panSlop: _panSlop);

  void tap(Offset at) {
    down(1, at);
    tracker.up(1, at, width: _width);
  }

  void drag(Offset from, Offset to, {int pointer = 1}) {
    down(pointer, from);
    tracker
      ..move(pointer, from + (to - from) / 2)
      ..move(pointer, to)
      ..up(pointer, to, width: _width);
  }

  group('legacy readers without native tap feedback', () {
    test('edge tap hides and notifies, center tap toggles', () {
      tap(const Offset(10, 300));
      tap(const Offset(390, 300));
      tap(const Offset(200, 300));
      expect(events, ['edge', 'edge', 'center']);
    });

    test('a drag past pan slop hides and notifies once, without a tap', () {
      drag(const Offset(200, 300), const Offset(100, 300));
      expect(events, ['hide', 'manual']);
    });

    test('jitter below pan slop does not hide or notify', () {
      // Moved past tap slop (not a tap) but below pan slop (not a drag).
      drag(const Offset(200, 300), const Offset(225, 300));
      expect(events, isEmpty);
    });
  });

  group('native paginated reader', () {
    setUp(() => tracker.nativeTapFeedback = true);

    test('taps are left to the native reader', () {
      tap(const Offset(10, 300));
      tap(const Offset(200, 300));
      expect(events, isEmpty);
    });

    test('a deliberate drag hides controls (existing swipe path still notifies)', () {
      drag(const Offset(300, 300), const Offset(100, 300));
      expect(events, ['hide', 'manual']);
    });

    test('small jitter hides nothing', () {
      drag(const Offset(300, 300), const Offset(310, 305));
      expect(events, isEmpty);
    });
  });

  group('native scroll reader', () {
    setUp(() {
      tracker
        ..nativeTapFeedback = true
        ..scrollMode = true;
    });

    test('taps anywhere keep following and are left to the native reader', () {
      tap(const Offset(5, 300));
      tap(const Offset(200, 300));
      expect(events, isEmpty);
    });

    test('a vertical drag in either direction hides controls and notifies once', () {
      drag(const Offset(200, 500), const Offset(200, 300));
      expect(events, ['hide', 'manual']);

      events.clear();
      drag(const Offset(200, 300), const Offset(200, 500));
      expect(events, ['hide', 'manual']);
    });

    test('notifies once per gesture however far it continues', () {
      down(1, const Offset(200, 500));
      for (var y = 480.0; y > 100; y -= 20) {
        tracker.move(1, Offset(200, y));
      }
      expect(events, ['hide', 'manual']);
    });

    test('jitter below pan slop does nothing', () {
      drag(const Offset(200, 300), const Offset(205, 320));
      expect(events, isEmpty);
    });

    test('a cross-axis drag hides controls but keeps following', () {
      drag(const Offset(300, 300), const Offset(100, 310));
      expect(events, ['hide']);
    });

    test('a second pointer hides controls but keeps following', () {
      down(1, const Offset(200, 300));
      down(2, const Offset(250, 300));
      expect(events, ['hide']);
    });

    test('a pointer joining a vertical drag does not notify afterwards', () {
      down(1, const Offset(200, 500));
      down(2, const Offset(250, 500));
      tracker.move(1, const Offset(200, 300));
      expect(events, ['hide']);
    });

    test('a lifted second pointer keeps the sequence multi-touch', () {
      down(1, const Offset(200, 500));
      down(2, const Offset(250, 500));
      tracker
        ..move(1, const Offset(200, 300))
        ..up(2, const Offset(250, 500), width: _width)
        ..move(1, const Offset(200, 100));
      expect(events, ['hide']);
    });

    test('each gesture starts fresh', () {
      drag(const Offset(200, 500), const Offset(200, 300));
      events.clear();
      tap(const Offset(200, 300));
      drag(const Offset(200, 500), const Offset(200, 300));
      expect(events, ['hide', 'manual']);
    });
  });

  group('ReadiumReaderChannel', () {
    test('onReaderReady reports whether the reader has native tap feedback', () async {
      final ready = <bool>[];
      final channel = ReadiumReaderChannel('test', onReaderReady: ready.add, onPageChanged: (_) {});

      await channel.onMethodCall(const MethodCall('onReaderReady', true));
      await channel.onMethodCall(const MethodCall('onReaderReady'));
      expect(ready, [true, false]);
    });

    test('onNativeTap forwards whether the tap toggles the controls', () async {
      final taps = <bool>[];
      final channel = ReadiumReaderChannel(
        'test',
        onReaderReady: (_) {},
        onPageChanged: (_) {},
        onNativeTap: taps.add,
      );

      await channel.onMethodCall(const MethodCall('onNativeTap', true));
      await channel.onMethodCall(const MethodCall('onNativeTap', false));
      expect(taps, [true, false]);
    });
  });
}
