import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

class ReadiumReaderWidget extends StatelessWidget {
  const ReadiumReaderWidget({
    required this.publication,
    this.loadingWidget = const Center(child: CircularProgressIndicator()),
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
    this.verticalScroll = false,
    super.key,
  });

  final Publication publication;
  final Widget loadingWidget;
  final Locator? initialLocator;
  final ValueNotifier<bool>? shouldShowControls;
  final Function(String)? onExternalLinkActivated;
  final ValueChanged<TextSelectionEvent>? onTextSelected;
  final ValueChanged<SelectionActionEvent>? onSelectionAction;
  final ValueChanged<DecorationInteractionEvent>? onDecorationInteraction;
  final List<SelectionAction> selectionActions;
  final Set<DefaultSelectionAction>? allowedDefaultActions;
  final String goBackwardSemanticLabel;
  final String goForwardSemanticLabel;
  final String toggleShowControlsSemanticLabel;
  final bool verticalScroll;

  @override
  Widget build(final BuildContext context) => Center(child: Text('ReaderWidget is not available on this platform.'));
}
