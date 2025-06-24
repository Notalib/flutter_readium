import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' as mq show Orientation;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:rxdart/rxdart.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'reader_channel.dart';

const _viewType = 'dk.nota.flutter_readium/ReadiumReaderWidget';

/// A ReadiumReaderWidget wraps a native Kotlin/Swift Readium navigator widget.
class ReadiumReaderWidget extends StatefulWidget {
  const ReadiumReaderWidget({
    required this.publication,
    this.loadingWidget = const Center(child: CircularProgressIndicator()),
    this.initialLocator,
    this.onTap,
    this.onGoLeft,
    this.onGoRight,
    this.onSwipe,
    this.onExternalLinkActivated,
    super.key,
  });

  final Publication publication;
  final Widget loadingWidget;
  final Locator? initialLocator;
  final VoidCallback? onTap;
  final VoidCallback? onGoLeft;
  final VoidCallback? onGoRight;
  final VoidCallback? onSwipe;
  final Function(String)? onExternalLinkActivated;

  @override
  State<StatefulWidget> createState() => _ReadiumReaderWidgetState();
}

class _ReadiumReaderWidgetState extends State<ReadiumReaderWidget>
    implements ReadiumReaderWidgetInterface {
  static const _wakelockTimerDuration = Duration(minutes: 30);

  /// Duration per retry to wait for native view to be ready.
  static const _awaitNativeViewReadyDuration = Duration(milliseconds: 20);

  /// Maximum number of retries to check, if native view is ready.
  static const _maxRetryAwaitNativeViewReady = 500;

  Timer? _wakelockTimer;
  ReadiumReaderChannel? _channel;

  /// Locator from native readium on page changed.
  // final _nativeTextLocator = BehaviorSubject<Locator?>.seeded(null);

  final _readium = FlutterReadiumPlatform.instance;

  late Widget _loadingWidget;
  mq.Orientation? _lastOrientation;

  late Widget _readerWidget;

  EPUBPreferences? get _defaultPreferences {
    return _readium.defaultPreferences;
  }

  @override
  void initState() {
    super.initState();
    R2Log.d('Widget initiated');

    // TODO: state removed

    _readerWidget = _buildNativeReader();

    _loadingWidget = GestureDetector(
      onTap: _onTap,
      child: widget.loadingWidget,
    );

    _enableWakelock();

    _setCurrentWidgetInterface();
  }

  @override
  void dispose() {
    R2Log.d('Widget disposed');
    _cleanup();
    _channel?.dispose();
    _channel = null;
    _lastOrientation = null;

    _disableWakelock();

    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    _onOrientationChangeWorkaround(MediaQuery.orientationOf(context));
    var userSwipe = false;

    return Listener(
      onPointerDown: (final _) {
        _enableWakelock();

        // TODO: state removed
      },
      onPointerMove: (final event) {
        if (userSwipe) {
          return;
        }

        userSwipe = event.delta.distance > 3.0;

        if (userSwipe) {
          widget.onSwipe?.call();
        }
      },
      onPointerUp: (final event) async {
        if (userSwipe) {
          /// Wait for page animation to complete.
          await Future.delayed(const Duration(seconds: 1));
        } else {
          final dx = event.position.dx;

          if (dx < 70.0) {
            widget.onGoLeft?.call();

            // Native Readium navigator already supports jumping to prev page.
            if (!Platform.isAndroid) {
              goLeft();
            }
          } else if (((context.size?.width ?? 0) - dx) < 70.0) {
            widget.onGoRight?.call();

            // Native Readium navigator already supports jumping to next page.
            if (!Platform.isAndroid) {
              goRight();
            }
          } else {
            _onTap();
          }
        }

        userSwipe = false;

        // TODO: state removed
      },
      onPointerCancel: (final _) {
        userSwipe = false;

        // TODO: state removed
      },
      child: _readerWidget,
    );
  }

  @override
  Future<void> go(
    final Locator locator, {
    required final bool isAudioBookWithText,
    final bool animated = false,
  }) async {
    R2Log.d(() => 'Go to $locator');

    _channel?.go(
      locator,
      animated: animated,
      isAudioBookWithText: isAudioBookWithText,
    );

    // await _awaitLocatorIsVisible();
    // _updateCurrentLocatorVisibility();

    R2Log.d('Done');
  }

  @override
  Future<void> goLeft({final bool animated = true}) async => _channel?.goLeft();

  @override
  Future<void> goRight({final bool animated = true}) async =>
      _channel?.goRight();

  @override
  Future<void> skipToNext({final bool animated = true}) async {
    List<Link>? toc = widget.publication.toc;
    if (toc == null || _currentLocator == null) {
      return;
    }
    String? currentHref = getTextLocatorHrefWithTocFragment(_currentLocator);

    // Ensure we are at least 1 page into the current chapter, if not in scroll mode.
    // TODO: Find a better way to do this, maybe a `lastVisibleLocator` ?
    if (_readium.defaultPreferences?.verticalScroll != true) {
      await _channel?.goRight(animated: false);
      final loc = await _channel?.getCurrentLocator();
      currentHref = getTextLocatorHrefWithTocFragment(loc);
    }

    int? curIndex = toc.indexWhere((l) => l.href == currentHref);
    if (curIndex > -1) {
      final newIndex = (curIndex + 1).clamp(0, toc.length - 1);
      Locator? nextChapter = widget.publication.locatorFromLink(toc[newIndex]);
      if (nextChapter != null) {
        await _channel?.go(nextChapter,
            isAudioBookWithText: false, animated: true);
      }
    }
  }

  @override
  Future<void> skipToPrevious({final bool animated = true}) async {
    List<Link>? toc = widget.publication.toc;
    if (toc == null || _currentLocator == null) {
      return;
    }
    String? currentHref = getTextLocatorHrefWithTocFragment(_currentLocator);
    int? curIndex = toc.indexWhere((l) => l.href == currentHref);
    if (curIndex > -1) {
      final newIndex = (curIndex - 1).clamp(0, toc.length - 1);
      Locator? previousChapter =
          widget.publication.locatorFromLink(toc[newIndex]);
      if (previousChapter != null) {
        await _channel?.go(previousChapter,
            isAudioBookWithText: false, animated: true);
      }
    }
  }

  @override
  Future<Locator?> getLocatorFragments(final Locator locator) async {
    R2Log.d('getLocatorFragments: $locator');

    await _awaitNativeViewReady();

    return await _channel?.getLocatorFragments(locator);
  }

  @override
  Future<Locator?> getCurrentLocator() async {
    R2Log.d('GetCurrentLocator()');
    return _channel?.getCurrentLocator();
  }

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    _channel?.setEPUBPreferences(preferences);
  }

  @override
  Future<void> applyDecorations(
      String id, List<ReaderDecoration> decorations) async {
    await _channel?.applyDecorations(id, decorations);
  }

  @override
  Future<void> ttsStart(String langCode, Locator? fromLocator) async {
    R2Log.d('TTS Start: $langCode');

    // When fromLocator is null => use firstVisibleLocator
    await _channel?.ttsStart(langCode, fromLocator);
  }

  @override
  Future<void> ttsStop() async {
    R2Log.d('TTS Stop');

    await _channel?.ttsStop();
  }

  void _onTap() => widget.onTap?.call();

  Widget _buildNativeReader() {
    final publication = widget.publication;

    R2Log.d(publication.identifier);

    final defaultPreferences = _defaultPreferences?.toJson();

    final creationParams = <String, dynamic>{
      'pubIdentifier': publication.identifier,
      'preferences': defaultPreferences,
      'initialLocator': widget.initialLocator == null
          ? null
          : json.encode(widget.initialLocator),
    };

    R2Log.d('creationParams=$creationParams');

    if (Platform.isAndroid) {
      return PlatformViewLink(
        viewType: _viewType,
        surfaceFactory: (final context, final controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const {},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
        onCreatePlatformView: (final params) =>
            PlatformViewsService.initSurfaceAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
              ..create(),
      );
    } else if (Platform.isIOS) {
      return UiKitView(
        viewType: _viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }
    return ColoredBox(
      color: const Color(0xffff00ff),
      child: Center(
        child: Text(
          'TODO — Implement ReadiumReaderWidget on ${Platform.operatingSystem}.',
        ),
      ),
    );
  }

  Future<void> _enableWakelock() async {
    R2Log.d('Ensure wakelock /w timer');

    WakelockPlus.enable();
    _wakelockTimer?.cancel();
    _wakelockTimer = Timer(_wakelockTimerDuration, _disableWakelock);
  }

  void _disableWakelock() {
    R2Log.d('Disable wakelock');

    WakelockPlus.disable();
    _wakelockTimer?.cancel();
  }

  void _setCurrentWidgetInterface() {
    R2Log.d('Set current reader in plugin');
    _readium.currentReaderWidget = this;
  }

  void _cleanup() {
    R2Log.d('cleanup ${_channel?.name}!');
    _readium.currentReaderWidget = null;
  }

  Locator? _currentLocator;

  void _onPlatformViewCreated(final int id) {
    _channel = ReadiumReaderChannel(
      '$_viewType:$id',
      onPageChanged: (final locator) {
        debugPrint('onPageChanged: ${locator.toJson()}');
        _currentLocator = locator;
      },
    );

    R2Log.d('New widget is: ${_channel?.name}');

    _awaitNativeViewReady().then((final _) {
      // TODO: This is just to demo how to use and debounce the Stream, remove when appropriate.
      final nativeLocatorStream = _readium.onTextLocatorChanged
          .debounceTime(const Duration(milliseconds: 50))
          .asBroadcastStream()
          .distinct();

      nativeLocatorStream.listen((locator) {
        R2Log.d('LocatorChanged - $locator');
      });
    });
  }

  Future<void> _awaitNativeViewReady() async {
    final nativeViewStartTime = DateTime.now();
    for (int retry = 0; retry < _maxRetryAwaitNativeViewReady; retry++) {
      if (await _channel?.isReaderReady() == true) {
        R2Log.d(
            'Native view is ready! Time spent: ${DateTime.now().difference(nativeViewStartTime).inMilliseconds} ms');
        return;
      }

      R2Log.d('Native reader not ready - retry:$retry');
      await Future.delayed(_awaitNativeViewReadyDuration);
    }

    R2Log.d(
        'Max retry reached! After ${DateTime.now().difference(nativeViewStartTime).inMilliseconds} ms');
  }

  /// Gets a Locator's href with toc fragment appended as identifier
  String? getTextLocatorHrefWithTocFragment(Locator? locator) {
    if (locator == null) {
      return null;
    }

    final txtLoc = locator.toTextLocator();
    final tocFragment = locator.locations?.fragments
        ?.firstWhereOrNull((f) => f.startsWith("toc="));
    if (tocFragment == null) {
      return null;
    }
    return '${txtLoc.toTextLocator().hrefPath.substring(1)}#${tocFragment.substring(4)}';
  }

  Future<void> _setLocation(
      final Locator locator, final bool isAudioBookWithText) async {
    R2Log.d('Set highlight');

    // final playbackRate = FlutterReadium.state.playbackRate;
    // final rateRatio = playbackRate == 0 ? 0 : 1 / playbackRate;
    // NOTE: Make duration shorter due to the frame animation.
    // final rate = playbackRate <= 1.0 ? rateRatio : rateRatio - rateRatio * 0.45;

    final locations = locator.locations;
    final domRange = locations?.domRange;
    final selector = domRange?.start.cssSelector ?? locations?.cssSelector;

    if (selector == null) {
      R2Log.d('No selector found: $locator');
      return;
    }

    // Make sure to copy fragment durations onto locators before sending over native channel.
    final fragmentDurationInSec =
        (locations?.xFragmentDuration?.inSeconds ?? 0);

    _channel?.setLocation(
      locator.mapLocations(
        (final locations) => locations.copyWithFragmentDuration(
          fragmentDurationInSec,
        ),
      ),
      isAudioBookWithText,
    );
  }

  /// TODO: Remove this workaround, if the underlying issue is completely fixed in Readium.
  ///
  /// If orientation changes, fix page alignment, so it doesn't stay on a weird-looking page 5½.
  void _onOrientationChangeWorkaround(final mq.Orientation orientation) async {
    if (_lastOrientation == null) {
      _lastOrientation = orientation;

      return;
    }

    // TODO: state removed
    await _awaitNativeViewReady();
    if (orientation != _lastOrientation) {
      // Remove domRange/cssSelector, so it navigates to a progression, which will always
      // trigger scrolling to the nearest page.
      if (_lastOrientation != null && _currentLocator != null) {
        Future.delayed(const Duration(milliseconds: 500)).then((final value) {
          R2Log.d(
              'Orientation changed. Re-navigating to current locator to re-align page.');
          R2Log.d('locator = $_currentLocator');
          _channel?.go(
            _currentLocator!,
            animated: false,
            isAudioBookWithText:
                false, // TODO: isAudioBookWithText - we don't know atm.
          );
        });
      }

      _lastOrientation = orientation;
    }
  }
}
