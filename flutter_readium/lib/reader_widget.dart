import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart' as mq show Orientation;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';
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
    this.shouldShowControls,
    this.onExternalLinkActivated,
    this.goBackwardSemanticLabel = 'Go Backward',
    this.goForwardSemanticLabel = 'Go Forward',
    this.toggleShowControlsSemanticLabel = 'Toggle show controls',
    this.verticalScroll = false,
    super.key,
  });

  final Publication publication;
  final Widget loadingWidget;
  final Locator? initialLocator;
  final ValueNotifier<bool>? shouldShowControls;
  final Function(String)? onExternalLinkActivated;
  final String goBackwardSemanticLabel;
  final String goForwardSemanticLabel;
  final String toggleShowControlsSemanticLabel;
  final bool verticalScroll;

  @override
  State<StatefulWidget> createState() => _ReadiumReaderWidgetState();
}

class _ReadiumReaderWidgetState extends State<ReadiumReaderWidget> implements ReadiumReaderWidgetInterface {
  static const _wakelockTimerDuration = Duration(minutes: 30);

  Timer? _wakelockTimer;
  ReadiumReaderChannel? _channel;
  bool wasDestroyed = false;
  bool isReady = false;

  final _isReadyCompleter = Completer<Locator>();

  final _readium = FlutterReadiumPlatform.instance;
  final FlutterReadium _flutterReadium = FlutterReadium();

  mq.Orientation? _lastOrientation;
  late Widget _readerWidget;

  EPUBPreferences? get _defaultPreferences {
    return _readium.defaultPreferences;
  }

  /// Last time that the controls were hidden due to a touch, used to guess whether a tap was caused
  /// by such a touch.
  DateTime? _lastTouchHideControls;

  @override
  void initState() {
    super.initState();
    R2Log.d('ReadiumReaderWidget initiated');

    _readerWidget = _buildNativeReader();
    _enableWakelock();
    _setCurrentWidgetInterface();
  }

  @override
  void dispose() {
    R2Log.d('ReadiumReaderWidget disposed');
    _cleanup();
    _channel?.dispose();
    _channel = null;
    _lastOrientation = null;

    _disableWakelock();
    wasDestroyed = true;

    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    _onOrientationChangeWorkaround(MediaQuery.orientationOf(context));
    var userSwipe = false;
    final verticalScroll = widget.verticalScroll;

    final readingProgression = widget.publication.metadata.readingProgression;
    // TODO: this presumes that ReadingProgression value btt or vertical scroll using btt is not ever used
    final leftUpLabel = readingProgression == ReadingProgression.rtl && !verticalScroll
        ? widget.goForwardSemanticLabel
        : widget.goBackwardSemanticLabel;
    final rightDownLabel = readingProgression == ReadingProgression.rtl && !verticalScroll
        ? widget.goBackwardSemanticLabel
        : widget.goForwardSemanticLabel;

    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          width: verticalScroll ? null : 70,
          height: verticalScroll ? 100 : null,
          right: verticalScroll ? 0 : null,
          bottom: verticalScroll ? null : 0,
          child: _buildSemanticsPrevNextPage(label: leftUpLabel, toNextPage: false),
        ),
        // TODO: This presumes there is only one semantic label, for when the different toggles
        Positioned.fill(child: _buildSemanticsToggleFullScreen(label: widget.toggleShowControlsSemanticLabel)),
        Positioned(
          top: verticalScroll ? null : 0,
          right: 0,
          width: verticalScroll ? null : 70,
          height: verticalScroll ? 100 : null,
          left: verticalScroll ? 0 : null,
          bottom: 0,
          child: _buildSemanticsPrevNextPage(label: rightDownLabel, toNextPage: true),
        ),
        ExcludeSemantics(
          child: Listener(
            onPointerDown: (final _) {
              _enableWakelock();
            },
            onPointerMove: (final event) {
              if (userSwipe) {
                return;
              }

              userSwipe = event.delta.distance > 3.0;

              if (userSwipe) {
                _onInteraction();
              }
            },
            onPointerUp: (final event) async {
              if (userSwipe) {
                /// Wait for page animation to complete.
                await Future.delayed(const Duration(seconds: 1));
              } else {
                final dx = event.position.dx;

                if (dx < 70.0 || ((context.size?.width ?? 0) - dx) < 70.0) {
                  // edge tap
                  _onInteraction();
                } else {
                  // center tap
                  _toggleControls();
                }
              }

              userSwipe = false;
            },

            child: _readerWidget,
          ),
        ),
      ],
    );
  }

  @override
  Future<void> go(final Locator locator, {required final bool isAudioBookWithText, final bool animated = false}) async {
    R2Log.d(() => 'Go to $locator');

    await _channel?.go(locator, animated: animated, isAudioBookWithText: isAudioBookWithText);

    R2Log.d('Done');
  }

  @override
  Future<void> goBackward({final bool animated = true}) async => _channel?.goBackward();

  @override
  Future<void> goForward({final bool animated = true}) async => _channel?.goForward();

  @override
  Future<void> skipToNext({final bool animated = true}) async {
    List<Link>? toc = widget.publication.toc;
    if (toc.isEmpty || _currentLocator == null) {
      return;
    }
    String? currentHref = getTextLocatorHrefWithTocFragment(_currentLocator);

    // Ensure we are at least 1 page into the current chapter, if not in scroll mode.
    // TODO: Find a better way to do this, maybe a `lastVisibleLocator` ?
    if (_readium.defaultPreferences?.verticalScroll != true) {
      await _channel?.goForward(animated: false);
      final loc = await _flutterReadium.onTextLocatorChanged.first;
      currentHref = getTextLocatorHrefWithTocFragment(loc);
    }

    int? curIndex = toc.indexWhere((l) => l.href == currentHref);
    if (curIndex > -1) {
      final newIndex = (curIndex + 1).clamp(0, toc.length - 1);
      Locator? nextChapter = widget.publication.locatorFromLink(toc[newIndex]);
      if (nextChapter != null) {
        await _channel?.go(nextChapter, isAudioBookWithText: false, animated: true);
      }
    }
  }

  @override
  Future<void> skipToPrevious({final bool animated = true}) async {
    List<Link>? toc = widget.publication.toc;
    if (toc.isEmpty || _currentLocator == null) {
      return;
    }
    String? currentHref = getTextLocatorHrefWithTocFragment(_currentLocator);
    int? curIndex = toc.indexWhere((l) => l.href == currentHref);
    if (curIndex > -1) {
      final newIndex = (curIndex - 1).clamp(0, toc.length - 1);
      Locator? previousChapter = widget.publication.locatorFromLink(toc[newIndex]);
      if (previousChapter != null) {
        await _channel?.go(previousChapter, isAudioBookWithText: false, animated: true);
      }
    }
  }

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    _channel?.setEPUBPreferences(preferences);
  }

  @override
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async {
    await _channel?.applyDecorations(id, decorations);
  }

  Widget _buildNativeReader() {
    final publication = widget.publication;

    R2Log.d(publication.identifier);

    final defaultPreferences = _defaultPreferences?.toJson();

    final creationParams = <String, dynamic>{
      'pubIdentifier': publication.identifier,
      'preferences': defaultPreferences,
      'initialLocator': widget.initialLocator == null ? null : json.encode(widget.initialLocator),
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
      child: Center(child: Text('TODO — Implement ReadiumReaderWidget on ${Platform.operatingSystem}.')),
    );
  }

  Future<void> _enableWakelock() async {
    R2Log.d('Ensure wakelock /w timer');

    WakelockPlus.enable();

    // Disable wakelock after 30 minutes of inactivity (no interaction with reader).
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

        if (isReady == false) {
          setState(() {
            isReady = true;
          });
          _isReadyCompleter.complete(locator);
        }
      },
    );

    R2Log.d('New widget is: ${_channel?.name}');
  }

  /// Gets a Locator's href with toc fragment appended as identifier
  String? getTextLocatorHrefWithTocFragment(Locator? locator) {
    if (locator == null) {
      return null;
    }

    final txtLoc = locator.toTextLocator();
    final tocFragment = locator.locations?.fragments.firstWhereOrNull((f) => f.startsWith("toc="));
    if (tocFragment == null) {
      return null;
    }
    return '${txtLoc.toTextLocator().hrefPath.substring(1)}#${tocFragment.substring(4)}';
  }

  /// TODO: Remove this workaround, if the underlying issue is completely fixed in Readium.
  ///
  /// If orientation changes, fix page alignment, so it doesn't stay on a weird-looking page 5½.
  void _onOrientationChangeWorkaround(final mq.Orientation orientation) async {
    if (_lastOrientation == null) {
      _lastOrientation = orientation;

      return;
    }

    if (!isReady) {
      return;
    }

    if (orientation != _lastOrientation) {
      // Remove domRange/cssSelector, so it navigates to a progression, which will always
      // trigger scrolling to the nearest page.
      if (_lastOrientation != null && _currentLocator != null) {
        Future.delayed(const Duration(milliseconds: 500)).then((final value) {
          R2Log.d('Orientation changed. Re-navigating to current locator to re-align page.');
          R2Log.d('locator = $_currentLocator');
          _channel?.go(
            _currentLocator!,
            animated: false,
            isAudioBookWithText: false, // TODO: isAudioBookWithText - we don't know atm.
          );
        });
      }

      _lastOrientation = orientation;
    }
  }

  void _toggleControls() {
    if (widget.shouldShowControls == null) return;

    final last = _lastTouchHideControls;
    final delta = last != null ? DateTime.now().difference(last) : null;
    // If we recently hid the controls due to a touch, assume that the tap is due to that same
    // touch, so don't re-show the controls.
    if (delta == null || delta > const Duration(milliseconds: 400)) {
      widget.shouldShowControls!.value = !widget.shouldShowControls!.value;
      // Debounce taps, since Readium apparently sends a double onTap on some devices.
      _lastTouchHideControls = DateTime.now();
    }
  }

  void _onInteraction() {
    if (widget.shouldShowControls?.value == true) {
      widget.shouldShowControls?.value = false;
      _lastTouchHideControls = DateTime.now();
    }
  }

  Widget _buildSemanticsPrevNextPage({required final String label, required final bool toNextPage}) {
    return Semantics(
      // TODO: this is not necessarily how it should be handled needs to be evaluated more
      sortKey: OrdinalSortKey(toNextPage ? 2.0 : 0.0),
      button: true,
      container: true,
      label: label,
      onTap: () => toNextPage ? _channel?.goForward() : _channel?.goBackward(),
      child: Container(color: Colors.transparent),
    );
  }

  Widget _buildSemanticsToggleFullScreen({required final String label}) {
    return Semantics(
      sortKey: const OrdinalSortKey(1.0),
      button: true,
      container: true,
      label: label,
      onTap: _toggleControls,
      child: Container(color: Colors.transparent),
    );
  }
}
