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
    this.selectionActions,
    this.allowedDefaultActions,
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
  final List<SelectionAction>? selectionActions;
  final Set<DefaultSelectionAction>? allowedDefaultActions;

  @override
  State<ReadiumReaderWidget> createState() => _ReadiumReaderWidgetState();
}

class _ReadiumReaderWidgetState extends State<ReadiumReaderWidget> implements ReadiumReaderWidgetInterface {
  static final _log = ReadiumLog.tag('ReaderWidget');

  @override
  void initState() {
    super.initState();
    _log.d('Widget initiated');
  }

  @override
  void dispose() {
    _log.d('Widget disposed');
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) => SizedBox.expand(
    child: ReadiumWebView(
      publication: widget.publication,
      currentLocator: widget.initialLocator,
      onTextSelected: widget.onTextSelected,
      onSelectionAction: widget.onSelectionAction,
      onDecorationInteraction: widget.onDecorationInteraction,
    ),
  );

  @override
  Future<void> go(final Locator locator, {required final bool isAudioBookWithText, final bool animated = false}) async {
    try {
      await JsPublicationChannel.goToLocation(locator.hrefPath);
    } on PlatformException catch (e, stackTrace) {
      final pubID = widget.publication.metadata.identifier;
      throw ReadiumError(
        'Error when navigating to locator: ${e.message}',
        code: e.code,
        data: 'publication id: $pubID. locator: $locator',
        stackTrace: stackTrace,
      );
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
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async {
    JsPublicationChannel().applyDecorations(
      id,
      json.encode(decorations.map((d) => d.toJson()).toList()),
    );
  }
}
