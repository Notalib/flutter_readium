import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' as mq show Orientation;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'flutter_readium.dart';
import 'reader_channel.dart';

const _viewType = 'dk.nota.flutter_readium/ReadiumReaderWidget';

/// A ReadiumReaderWidget wraps a native Kotlin/Swift Readium navigator widget.
class ReadiumReaderWidget extends StatefulWidget {
  const ReadiumReaderWidget({
    required this.publication,
    this.loadingWidget,
    this.initialLocator,
    this.shouldShowControls,
    this.onExternalLinkActivated,
    this.onTextSelected,
    this.onSelectionAction,
    this.onDecorationInteraction,
    this.selectionActions = const [],
    this.allowedDefaultActions,
    this.goBackwardSemanticLabel = 'Go Backward',
    this.goForwardSemanticLabel = 'Go Forward',
    this.toggleShowControlsSemanticLabel = 'Toggle show controls',
    this.preloadPreviousPositionCount = 2,
    this.preloadNextPositionCount = 6,
    super.key,
  });

  /// The publication to display, obtained from [FlutterReadium.openPublication].
  final Publication publication;

  /// Optional widget to show while the reader is loading, e.g. a spinner.
  /// It will be shown until the reader sends its first onPageChanged event.
  /// It should typically be a full-screen widget, since it will be stacked on top of the reader widget.
  final Widget? loadingWidget;

  /// Optional locator to restore a previously saved reading position. `null` starts from the beginning.
  final Locator? initialLocator;

  /// Notifier that tells client whether it should show controls, based on user-interaction with the native viewer.
  final ValueNotifier<bool>? shouldShowControls;

  /// Callback invoked when the reader activates an external (non-publication) link.
  final Function(String)? onExternalLinkActivated;

  /// Callback invoked when the user selects text in the reader.
  final ValueChanged<TextSelectionEvent>? onTextSelected;

  /// Callback invoked when the user taps a configured editing action on selected text.
  final ValueChanged<SelectionActionEvent>? onSelectionAction;

  /// Callback invoked when the user interacts with an existing decoration (e.g. taps a highlight).
  final ValueChanged<DecorationInteractionEvent>? onDecorationInteraction;

  /// Native context menu actions shown when text is selected.
  final List<SelectionAction> selectionActions;

  /// Controls which system-provided actions appear in the text selection menu.
  ///
  /// If `null` (the default), all platform defaults are shown (Copy, Share, etc.).
  /// If an empty set, only custom [selectionActions] are shown.
  /// Otherwise, only the specified system actions are included.
  ///
  /// Note: [DefaultSelectionAction.translate] is iOS-only; [DefaultSelectionAction.selectAll]
  /// is Android-only. Unsupported values for a platform are silently ignored.
  final Set<DefaultSelectionAction>? allowedDefaultActions;

  /// Accessibility label for the backward navigation semantic region.
  final String goBackwardSemanticLabel;

  /// Accessibility label for the forward navigation semantic region.
  final String goForwardSemanticLabel;

  /// Accessibility label for the controls toggle semantic region.
  final String toggleShowControlsSemanticLabel;

  /// Number of resource positions to preload before the current one. Default `2`.
  /// Higher values smooth out backward navigation at the cost of memory; consider
  /// increasing for local publications and lowering for remote ones.
  ///
  /// iOS only. kotlin-toolkit does not expose this on its public navigator
  /// configuration, so the value is ignored on Android.
  final int preloadPreviousPositionCount;

  /// Number of resource positions to preload after the current one. Default `6`.
  /// See [preloadPreviousPositionCount] for tradeoffs and platform support.
  final int preloadNextPositionCount;

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

  mq.Orientation? _lastOrientation;
  late Widget _readerWidget;

  EPUBPreferences? get _defaultPreferences => _readium.defaultPreferences;

  bool _scrollMode = false;

  /// Last time that the controls were hidden due to a touch, used to guess whether a tap was caused
  /// by such a touch.
  DateTime? _lastTouchHideControls;

  @override
  void initState() {
    super.initState();
    ReadiumLog.d('ReadiumReaderWidget init');

    _readerWidget = _buildNativeReader();
    _enableWakelock();
    _setCurrentWidgetInterface();
    _scrollMode = _defaultPreferences?.scroll ?? false;
  }

  @override
  void dispose() {
    ReadiumLog.d('ReadiumReaderWidget dispose');
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

    final readingProgression = widget.publication.metadata.readingProgression;
    // TODO: this presumes that ReadingProgression value btt or vertical scroll using btt is not ever used
    final leftUpLabel = readingProgression == ReadingProgression.rtl && !_scrollMode
        ? widget.goForwardSemanticLabel
        : widget.goBackwardSemanticLabel;
    final rightDownLabel = readingProgression == ReadingProgression.rtl && !_scrollMode
        ? widget.goBackwardSemanticLabel
        : widget.goForwardSemanticLabel;

    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          width: _scrollMode ? null : 70,
          height: _scrollMode ? 100 : null,
          right: _scrollMode ? 0 : null,
          bottom: _scrollMode ? null : 0,
          child: _buildSemanticsPrevNextPage(label: leftUpLabel, toNextPage: false),
        ),
        // TODO: This presumes there is only one semantic label, for when the different toggles
        Positioned.fill(child: _buildSemanticsToggleFullScreen(label: widget.toggleShowControlsSemanticLabel)),
        Positioned(
          top: _scrollMode ? null : 0,
          right: 0,
          width: _scrollMode ? null : 70,
          height: _scrollMode ? 100 : null,
          left: _scrollMode ? 0 : null,
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
        if (!isReady && widget.loadingWidget != null) Positioned.fill(child: widget.loadingWidget!),
      ],
    );
  }

  @override
  Future<void> go(final Locator locator, {required final bool isAudioBookWithText, final bool animated = false}) async {
    ReadiumLog.d(() => 'Go to $locator');

    await _channel?.go(locator, animated: animated, isAudioBookWithText: isAudioBookWithText);

    ReadiumLog.d('Go to locator completed');
  }

  @override
  Future<void> goBackward({final bool animated = true}) async => _channel?.goBackward();

  @override
  Future<void> goForward({final bool animated = true}) async => _channel?.goForward();

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    _channel?.setEPUBPreferences(preferences);

    _scrollMode = preferences.scroll ?? false;
  }

  @override
  Future<void> setPDFPreferences(PDFPreferences preferences) async {
    _channel?.setPDFPreferences(preferences);
  }

  @override
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async {
    await _channel?.applyDecorations(id, decorations);
  }

  Widget _buildNativeReader() {
    final publication = widget.publication;

    ReadiumLog.d(publication.identifier);

    final defaultPreferences = _defaultPreferences?.toJson();

    final creationParams = <String, dynamic>{
      'pubIdentifier': publication.identifier,
      'preferences': defaultPreferences,
      'initialLocator': widget.initialLocator == null ? null : json.encode(widget.initialLocator),
      'preloadPreviousPositionCount': widget.preloadPreviousPositionCount,
      'preloadNextPositionCount': widget.preloadNextPositionCount,
      if (widget.selectionActions.isNotEmpty)
        'selectionActions': widget.selectionActions.map((a) => a.toJson()).toList(),
      if (widget.allowedDefaultActions != null)
        'allowedDefaultActions': widget.allowedDefaultActions!.map((a) => a.serialized).toList(),
    };

    ReadiumLog.d('creationParams=$creationParams');

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
    ReadiumLog.d('Ensure wakelock /w timer');

    WakelockPlus.enable();

    // Disable wakelock after 30 minutes of inactivity (no interaction with reader).
    _wakelockTimer?.cancel();
    _wakelockTimer = Timer(_wakelockTimerDuration, _disableWakelock);
  }

  void _disableWakelock() {
    ReadiumLog.d('Disable wakelock');

    WakelockPlus.disable();
    _wakelockTimer?.cancel();
  }

  void _setCurrentWidgetInterface() {
    ReadiumLog.d('Set current reader in plugin');
    // ignore: invalid_use_of_protected_member
    _readium.currentReaderWidget = this;
  }

  void _cleanup() {
    ReadiumLog.d('cleanup ${_channel?.name}!');
    // ignore: invalid_use_of_protected_member
    _readium.currentReaderWidget = null;
  }

  Locator? _currentLocator;

  void _onPlatformViewCreated(final int id) {
    _channel = ReadiumReaderChannel(
      '$_viewType:$id',
      onPageChanged: (final locator) {
        ReadiumLog.d(() => 'onPageChanged: ${locator.toJson()}');
        _currentLocator = locator;

        if (isReady == false) {
          setState(() {
            isReady = true;
          });
          _isReadyCompleter.complete(locator);
        }
      },
      onTextSelected: widget.onTextSelected,
      onSelectionAction: widget.onSelectionAction,
      onDecorationInteraction: widget.onDecorationInteraction,
    );

    if (widget.selectionActions.isNotEmpty) {
      _channel!.configureSelectionActions(widget.selectionActions);
    }

    ReadiumLog.d('New widget is: ${_channel?.name}');
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
          ReadiumLog.d('Orientation changed. Re-navigating to current locator to re-align page.');
          ReadiumLog.d('locator = $_currentLocator');
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

  Widget _buildSemanticsPrevNextPage({required final String label, required final bool toNextPage}) => Semantics(
    // TODO: this is not necessarily how it should be handled needs to be evaluated more
    sortKey: OrdinalSortKey(toNextPage ? 2.0 : 0.0),
    button: true,
    container: true,
    label: label,
    onTap: () => toNextPage ? _channel?.goForward() : _channel?.goBackward(),
    child: Container(color: Colors.transparent),
  );

  Widget _buildSemanticsToggleFullScreen({required final String label}) => Semantics(
    sortKey: const OrdinalSortKey(1.0),
    button: true,
    container: true,
    label: label,
    onTap: _toggleControls,
    child: Container(color: Colors.transparent),
  );
}
