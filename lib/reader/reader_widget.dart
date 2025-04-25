import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart' as mq show Orientation;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../_index.dart';
import 'reader_channel.dart';

const _viewType = 'dk.nota.flutter_readium/ReadiumReaderWidget';

/// A ReadiumReaderWidget wraps a native Kotlin/Swift Readium navigator widget.
class ReadiumReaderWidget extends StatefulWidget {
  const ReadiumReaderWidget({
    this.loadingWidget = const Center(child: CircularProgressIndicator()),
    this.onTap,
    this.onGoLeft,
    this.onGoRight,
    this.onSwipe,
    super.key,
  });

  final Widget loadingWidget;
  final VoidCallback? onTap;
  final VoidCallback? onGoLeft;
  final VoidCallback? onGoRight;
  final VoidCallback? onSwipe;

  @override
  State<StatefulWidget> createState() => _ReadiumReaderWidgetState();
}

class _ReadiumReaderWidgetState extends State<ReadiumReaderWidget>
    implements ReadiumReaderWidgetInterface {
  static const _wakelockTimerDuration = Duration(minutes: 30);
  static const _maxRetryAwaitLocatorVisible = 20;
  static const _maxRetryAwaitNativeViewReady = 10;
  Timer? _wakelockTimer;
  ReadiumReaderChannel? _channel;

  /// Locator from native readium on page changed.
  final _nativeTextLocator = BehaviorSubject<Locator?>.seeded(null);

  final _readium = FlutterReadium.instance;
  late Widget _loadingWidget;
  mq.Orientation? _lastOrientation;

  late Widget _readerWidget;

  @override
  void initState() {
    super.initState();
    R2Log.d('Widget initiated');

    FlutterReadium.updateState(
      readerStatus: ReadiumReaderStatus.loading,
    );

    _readerWidget = _buildNativeReader();

    _loadingWidget = GestureDetector(
      onTap: _onTap,
      child: widget.loadingWidget,
    );

    _enableWakelock();

    _setWidgetInterface();
  }

  @override
  void dispose() {
    R2Log.d('Widget disposed');
    _cleanup();
    _channel?.dispose();
    _channel = null;
    _lastOrientation = null;

    FlutterReadium.updateState(
      readerStatus: ReadiumReaderStatus.close,
    );

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

        final state = FlutterReadium.state;

        FlutterReadium.updateState(
          readerSwiping: true,
          textLocator: state.textLocator?.copyWith(
            locations: state.textLocator?.locations?.copyWith(customProgressionOverride: null),
          ),
        );
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

        FlutterReadium.updateState(
          readerSwiping: false,
        );
      },
      onPointerCancel: (final _) {
        userSwipe = false;

        FlutterReadium.updateState(
          readerSwiping: false,
        );
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: _readerWidget,
          ),
          Positioned.fill(
            child: StreamBuilder<bool>(
              initialData: false,
              stream: FlutterReadium.stateStream.readerReadyUntilReaderClosed,
              builder: (final context, final snapshot) =>
                  snapshot.data == true ? const SizedBox.shrink() : _loadingWidget,
            ),
          ),
        ],
      ),
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

    await _awaitLocatorIsVisible();
    _updateCurrentLocatorVisibility();

    R2Log.d('Done');
  }

  @override
  Future<void> goLeft({final bool animated = true}) async => _channel?.goLeft();

  @override
  Future<void> goRight({final bool animated = true}) async => _channel?.goRight();

  @override
  Future<Locator?> getLocatorFragments(final Locator locator) async {
    R2Log.d('getLocatorFragments: $locator');

    await FlutterReadium.state.awaitReaderReady;

    return _channel?.getLocatorFragments(locator);
  }

  void _onTap() => widget.onTap?.call();

  Widget _buildNativeReader() => StreamBuilder<Publication?>(
        stream: FlutterReadium.stateStream.publication,
        initialData: FlutterReadium.state.publication,
        builder: (final context, final publicationSnapshot) {
          final publication = publicationSnapshot.data;

          if (publication == null) {
            return _loadingWidget;
          }

          return AnimatedSwitcher(
            key: ValueKey(publication.identifier),
            duration: const Duration(milliseconds: 400),
            child: FutureBuilder(
              key: ValueKey(publication.identifier),
              future: ReadiumReaderChannel.writeUserPropertiesFile(
                FlutterReadium.state.readerProperties,
              ),
              builder: (final context, final userPropertiesReadySnapshot) {
                if (userPropertiesReadySnapshot.connectionState != ConnectionState.done) {
                  return _loadingWidget;
                }

                R2Log.d(publication.identifier);

                final properties = FlutterReadium.state.readerProperties.toJson();

                final locator = FlutterReadium.state.currentLocator?.toTextLocator();

                final creationParams = <String, dynamic>{
                  'userProperties': properties,
                  if (Platform.isAndroid)
                    'userPropertiesPath': ReadiumReaderChannel.userPropertiesPath,
                  'initialLocator': locator == null ? null : json.encode(locator),
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
              },
            ),
          );
        },
      );

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

  Future<void> _observeReaderProperties() async {
    R2Log.d('Observing');

    // Skip first event, since properties also get set while building the native reader.
    final propertiesStream = FlutterReadium.stateStream.readerPropertiesUntilReaderClosed;
    await for (final properties in propertiesStream.skip(1)) {
      R2Log.d('Changed - $properties');
      try {
        ReadiumReaderChannel.writeUserPropertiesFile(properties);

        await FlutterReadium.state.awaitReaderReady;

        _channel?.setUserProperties(properties);

        final state = FlutterReadium.state;
        final locator = state.ttsOrAudiobook && state.audioMatchesText
            ? FlutterReadium.state.currentLocator
            : FlutterReadium.state.textLocator;

        if (locator != null) {
          _channel?.go(locator, isAudioBookWithText: state.isAudiobookWithText);
        }
      } on Object catch (error) {
        R2Log.d('Error - $error');

        FlutterReadium.updateState(
          error: ReadiumError(
            'Failed to set user properties error $error',
            data: properties,
          ),
        );
      }
    }

    R2Log.d('Done');
  }

  void _setWidgetInterface() {
    R2Log.d('Set reader in readium');
    _readium.reader = this;
  }

  void _cleanup() {
    R2Log.d('cleanup ${_channel?.name}!');

    FlutterReadium.updateState(
      readerStatus: ReadiumReaderStatus.close,
    );
    _readium.reader = null;
  }

  void _onPlatformViewCreated(final int id) {
    _channel = ReadiumReaderChannel(
      '$_viewType:$id',
      onPageChanged: (final locator) {
        _nativeTextLocator.value = locator;
      },
    );

    R2Log.d('New widget is ${_channel?.name}!');

    _awaitLocatorIsVisible().then((final _) {
      FlutterReadium.updateState(
        readerStatus: ReadiumReaderStatus.open,
      );

      _observeLocatorOnPageChanged();
      _observeReaderProperties();
      _observeAudioLocator();
    });
  }

  void _observeAudioLocator() async {
    R2Log.d('Observing');

    String? lastHrefPath;

    final locatorStream = FlutterReadium.stateStream.audioLocatorUntilReaderClosed
        .where((final locator) => locator != null)
        .map((final locator) => locator!)
        .distinct((final a, final b) {
      final state = FlutterReadium.state;

      if (state.isAudiobook) {
        return a.locations?.cssSelector == b.locations?.cssSelector;
      }

      if (state.isEbook && state.ttsEnabled) {
        return a.locations?.domRange == b.locations?.domRange;
      }

      return a.locations?.progression == b.locations?.progression &&
          a.locations?.cssSelector == b.locations?.cssSelector &&
          a.locations?.domRange == b.locations?.domRange;
    });

    await for (final locator in locatorStream) {
      R2Log.d('Changed - $locator');

      final state = FlutterReadium.state;

      if (!state.ttsOrAudiobook) {
        R2Log.d('No need to tack audioLocator - skip');
        continue;
      }

      final pub = state.publication;

      if (pub == null) {
        R2Log.d('Pub not set - skip');

        continue;
      }

      if (!state.readerSwiping && (state.audioMatchesText || !state.playing)) {
        if (FlutterReadium.state.ttsEnabled && lastHrefPath == null) {
          // Probably tts just started, no need to set the reader status to loading.

          lastHrefPath = locator.hrefPath;
        } else if (lastHrefPath != null && lastHrefPath != locator.hrefPath) {
          FlutterReadium.updateState(
            readerStatus: ReadiumReaderStatus.loading,
          );

          lastHrefPath = locator.hrefPath;
        }

        if (FlutterReadium.state.readerStatus.isLoading) {
          R2Log.d('Wait for native reader to be ready');

          await _awaitNativeViewReady();
        }

        R2Log.d('Safe to go');
        _channel?.go(locator, animated: true, isAudioBookWithText: state.isAudiobookWithText);
      }

      FlutterReadium.state.awaitReaderReady.then((final _) {
        _setLocation(locator, state.isAudiobookWithText);
        _updateCurrentLocatorVisibility();
      });
    }

    R2Log.d('Done');
  }

  Future<void> _awaitNativeViewReady([int retry = 0]) async {
    R2Log.d('attempt: $retry');

    if (retry >= _maxRetryAwaitNativeViewReady) {
      R2Log.d('Max retry reached!');

      return;
    }

    final state = FlutterReadium.state;

    if (!state.hasPub) {
      R2Log.d('Probebly publication is closed while awaiting for locator');

      return;
    }

    final channel = _channel;

    if (channel == null) {
      R2Log.d('Channel not set - retry');

      await Future.delayed(const Duration(seconds: 1));

      return _awaitNativeViewReady(++retry);
    }

    if (!await channel.isReaderReady()) {
      R2Log.d(() => 'Native reader not ready - retry');

      await Future.delayed(const Duration(milliseconds: 100));

      return _awaitNativeViewReady(++retry);
    }
  }

  Future<void> _setLocation(final Locator locator, final bool isAudioBookWithText) async {
    R2Log.d('Set highlight');

    final playbackRate = FlutterReadium.state.playbackRate;
    final rateRatio = playbackRate == 0 ? 0 : 1 / playbackRate;
    // NOTE: Make duration shorter due to the frame animation.
    final rate = playbackRate <= 1.0 ? rateRatio : rateRatio - rateRatio * 0.45;

    final locations = locator.locations;
    final domRange = locations?.domRange;
    final selector = domRange?.start.cssSelector ?? locations?.cssSelector;

    if (selector == null) {
      R2Log.d('No selector found: $locator');
      return;
    }

    // Make sure to copy fragment durations onto locators before sending over native channel.
    final fragmentDurationInSec = (locations?.xFragmentDuration?.inSeconds ?? 0) * rate;

    _channel?.setLocation(
      locator.mapLocations(
        (final locations) => locations.copyWithFragmentDuration(
          fragmentDurationInSec,
        ),
      ),
      isAudioBookWithText,
    );
  }

  Future<void> _updateCurrentLocatorVisibility() async {
    final state = FlutterReadium.state;
    final locator = state.currentLocator;

    R2Log.d('$locator');

    if (locator == null) {
      return;
    }

    if (!FlutterReadium.state.readerReady || (state.isEbook && !state.ttsEnabled)) {
      FlutterReadium.updateState(
        audioMatchesText: true,
      );

      return;
    }

    // Remember whether the spoken part is visible. If currently visible, track the spoken part as
    // it moves. If not visible, don't track it. If there is no spoken part, don't change whether
    // we're tracking it or not.
    final locatorVisible = await _channel?.isLocatorVisible(locator);

    FlutterReadium.updateState(
      audioMatchesText: FlutterReadium.state.readerReady && locatorVisible != false,
    );

    R2Log.d('Update Done');
  }

  Future<void> _awaitLocatorIsVisible([int retry = 0]) async {
    R2Log.d('attempt: $retry');

    if (retry >= _maxRetryAwaitLocatorVisible) {
      R2Log.d('Max retry reached!');

      return;
    }

    final state = FlutterReadium.state;

    if (!state.hasPub) {
      R2Log.d('Probebly publication is closed while awaiting for locator');

      return;
    }

    final locator = state.currentLocator;
    final channel = _channel;

    if (channel == null || locator == null) {
      R2Log.d('Either Channel or locator not set - retry  channel: $_channel - $locator ');

      await Future.delayed(const Duration(seconds: 1));

      return _awaitLocatorIsVisible(++retry);
    }

    if (state.readerStatus.isLoading) {
      await _awaitNativeViewReady();
    }

    if (!await channel.isLocatorVisible(locator)) {
      R2Log.d('locator not visible - retry $locator');

      channel.go(locator, isAudioBookWithText: state.isAudiobookWithText);

      await Future.delayed(const Duration(milliseconds: 100));

      return _awaitLocatorIsVisible(++retry);
    }
  }

  Future<void> _observeLocatorOnPageChanged() async {
    R2Log.d('Observing');

    // Skip first event, since properties also get set while building the native reader.
    final nativeLocatorStream = TakeUntilExtension(_nativeTextLocator)
        .takeUntil(FlutterReadium.stateStream.readerClosed)
        .debounceTime(const Duration(milliseconds: 100))
        .where((final locator) => locator != null)
        .map((final locator) => locator!)
        .asBroadcastStream()
        .distinct();

    await for (final locator in nativeLocatorStream) {
      R2Log.d('Changed - $locator');
      try {
        final state = FlutterReadium.state;

        final pub = state.publication;
        final locatorPath = Uri.tryParse(locator.href)?.path;
        final readingOrder = pub?.readingOrder;
        final readingOrderIndex = readingOrder?.indexWhere(
              (final readingOrder) => Uri.tryParse(readingOrder.href)?.path == locatorPath,
            ) ??
            -1;

        final locations = locator.locations;
        final page = locations?.page;
        final totalPages = locations?.totalPages;

        // Native progression is calculated wrong, so the first page isn't at 0% and last page isn't at
        // 100%.
        double? progressionOverride;
        if (page == null || totalPages == null) {
          progressionOverride = null;
        } else if (page == totalPages) {
          progressionOverride = 1.0;
        } else if (page == 1) {
          progressionOverride = 0;
        } else {
          progressionOverride = page / max(totalPages, 1.0);
        }

        final progression = progressionOverride ?? locator.locations?.progression ?? 0.0;
        final index = readingOrderIndex == -1 ? 0 : readingOrderIndex;
        final progressions = pub?.calculateProgressions(index: index, progression: progression);

        final link = readingOrderIndex == -1 ? null : readingOrder![readingOrderIndex];
        final title = locator.title ?? link?.title;

        final textLocator = locator.copyWith(
          title: title,
          type: MediaType.html.value,
          locations: locator.locationsOrEmpty.copyWith(
            totalProgression: progressions?.totalProgression,
            customProgressionOverride: state.textLocator?.locations?.customProgressionOverride,
            progression: progressions?.progression,
            fragments: [
              ...?locator.locationsOrEmpty.fragments,
            ],
            position: index + 1,
          ),
        );

        FlutterReadium.updateState(
          readerStatus: locator.locations?.totalProgression == 1.0
              ? ReadiumReaderStatus.endOfPublication
              : ReadiumReaderStatus.open,
          textLocator: textLocator,
        );

        _updateCurrentLocatorVisibility();
      } on Object catch (error) {
        R2Log.d('Error - $error');
      }
    }

    R2Log.d('Done');
  }

  /// TODO: Remove this workaround, if the underlying issue is completely fixed in Readium.
  ///
  /// If orientation changes, fix page alignment, so it doesn't stay on a weird-looking page 5½.
  void _onOrientationChangeWorkaround(final mq.Orientation orientation) async {
    if (_lastOrientation == null) {
      _lastOrientation = orientation;

      return;
    }

    await FlutterReadium.state.awaitReaderReady;
    if (orientation != _lastOrientation) {
      // Remove domRange/cssSelector, so it navigates to a progression, which will always
      // trigger scrolling to the nearest page.
      final locator = FlutterReadium.state.textLocator?.mapLocations(
        (final locations) => locations.copyWith(
          domRange: null,
          cssSelector: null,
        ),
      );
      if (_lastOrientation != null && locator != null) {
        Future.delayed(const Duration(milliseconds: 500)).then((final value) {
          R2Log.d('Orientation changed. Re-navigating to current locator to re-align page.');
          R2Log.d('locator = $locator');
          _channel?.go(
            locator,
            animated: false,
            isAudioBookWithText: FlutterReadium.state.isAudiobookWithText,
          );
        });
      }

      _lastOrientation = orientation;
    }
  }
}
