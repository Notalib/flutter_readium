import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'flutter_readium.dart';
import 'src/index.dart';

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
    this.onTextSelected,
    this.onSelectionAction,
    this.onDecorationInteraction,
    this.onImageTapped,
    this.selectionActions,
    this.allowedDefaultActions,
    this.fontFamilyDeclarations = const [],
    this.disablePageTurnsWhileScrolling = false,
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
  final void Function(TextSelectionEvent)? onTextSelected;
  final void Function(SelectionActionEvent)? onSelectionAction;
  final void Function(DecorationInteractionEvent)? onDecorationInteraction;
  final ValueChanged<ImageTapEvent>? onImageTapped;

  /// Actions shown in a floating toolbar above the selected text.
  ///
  /// Web draws the toolbar itself, since the browser's selection menu cannot be extended.
  final List<SelectionAction>? selectionActions;

  /// Not supported on web: the browser's native selection menu cannot be customised, so this is ignored.
  final Set<DefaultSelectionAction>? allowedDefaultActions;
  final List<ReaderFontFamily> fontFamilyDeclarations;
  final bool disablePageTurnsWhileScrolling;

  @override
  State<ReadiumReaderWidget> createState() => _ReadiumReaderWidgetState();
}

class _ReadiumReaderWidgetState extends State<ReadiumReaderWidget> implements ReadiumReaderWidgetInterface {
  static final _log = ReadiumLog.tag('ReaderWidget');

  @override
  void initState() {
    super.initState();
    _log.d('Widget initiated');
    _pushSelectionActions();
  }

  @override
  void didUpdateWidget(covariant ReadiumReaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_actionsJson(oldWidget) != _actionsJson(widget)) {
      _pushSelectionActions();
    }
  }

  // No reset on dispose: the reader is a singleton, so a replacing widget may
  // already have pushed its own actions, and every widget pushes on init.
  @override
  void dispose() {
    _log.d('Widget disposed');
    super.dispose();
  }

  static String _actionsJson(ReadiumReaderWidget w) =>
      json.encode((w.selectionActions ?? const <SelectionAction>[]).map((a) => a.toJson()).toList());

  // The toolbar is a nicety; a JS failure must not break widget init.
  void _pushSelectionActions() {
    try {
      JsPublicationChannel().setSelectionActions(_actionsJson(widget));
    } on PlatformException catch (e) {
      _log.w('setSelectionActions failed: $e');
    }
  }

  @override
  Widget build(final BuildContext context) => SizedBox.expand(
    child: ReadiumWebView(
      publication: widget.publication,
      currentLocator: widget.initialLocator,
      fontFamilyDeclarations: widget.fontFamilyDeclarations,
      onTextSelected: widget.onTextSelected,
      onSelectionAction: widget.onSelectionAction,
      onDecorationInteraction: widget.onDecorationInteraction,
      onImageTapped: widget.onImageTapped,
    ),
  );

  @override
  Future<void> go(
    final Locator locator, {
    required final bool isAudioBookWithText,
    final bool animated = false,
  }) async {
    try {
      await JsPublicationChannel.goToLocator(json.encode(locator));
    } on PlatformException catch (e) {
      throw ReadiumException.fromPlatformException(e);
    }
  }

  @override
  Future<void> goBackward({final bool animated = true}) async {
    JsPublicationChannel.goBackward();
  }

  @override
  Future<void> goForward({final bool animated = true}) async {
    JsPublicationChannel.goForward();
  }

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    _log.d('setEPUBPreferences not implemented in web version');
  }

  @override
  Future<void> setPDFPreferences(PDFPreferences preferences) async {
    _log.d('setPDFPreferences not supported on web');
  }

  @override
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) async {
    JsPublicationChannel().applyDecorations(
      id,
      json.encode(decorations.map((d) => d.toJson()).toList()),
    );
  }
}
