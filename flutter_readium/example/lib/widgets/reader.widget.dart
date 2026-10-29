import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../state/index.dart';
import 'full_screen_image_view.dart';
import 'highlight_sheet.widget.dart';

final _customFontFamilies = [
  ReaderFontFamily(
    name: 'Atkinson Hyperlegible',
    fallbacks: const ['sans-serif'],
    faces: const [
      ReaderFontFace(
        asset: 'assets/fonts/AtkinsonHyperlegible/AtkinsonHyperlegible-Regular.ttf',
      ),
      ReaderFontFace(
        asset: 'assets/fonts/AtkinsonHyperlegible/AtkinsonHyperlegible-Italic.ttf',
        style: ReaderFontStyle.italic,
      ),
      ReaderFontFace(
        asset: 'assets/fonts/AtkinsonHyperlegible/AtkinsonHyperlegible-Bold.ttf',
        weight: 700,
      ),
      ReaderFontFace(
        asset: 'assets/fonts/AtkinsonHyperlegible/AtkinsonHyperlegible-BoldItalic.ttf',
        style: ReaderFontStyle.italic,
        weight: 700,
      ),
    ],
  ),
];

class ReaderWidget extends StatelessWidget {
  const ReaderWidget({this.shouldShowControls, super.key});

  final ValueNotifier<bool>? shouldShowControls;

  @override
  Widget build(
    final BuildContext context,
  ) => BlocBuilder<PublicationBloc, PublicationState>(
    buildWhen: (prev, next) => prev.hasNonHighlightChanges(next),
    builder: (final context, final state) {
      if (state.isLoading) {
        return const Center(child: CircularProgressIndicator());
      } else if (state.error != null) {
        return ColoredBox(
          color: Colors.yellow.shade400,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Loading publication failed.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  Text(state.errorDebugDescription()),
                ],
              ),
            ),
          ),
        );
      } else if (state.publication != null) {
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: Stack(
            children: [
              ReadiumReaderWidget(
                publication: state.publication!,
                initialLocator: state.initialLocator,
                fontFamilyDeclarations: _customFontFamilies,
                shouldShowControls: shouldShowControls,
                allowedDefaultActions: const {
                  DefaultSelectionAction.copy,
                  DefaultSelectionAction.share,
                  DefaultSelectionAction.translate,
                },
                selectionActions: const [
                  SelectionAction(id: 'highlight', title: 'Highlight'),
                  SelectionAction(id: 'note', title: 'Add Note'),
                ],
                onTextSelected: (event) {
                  debugPrint('[Selection] text="${event.selectedText}"');
                },
                onSelectionAction: (event) => handleSelectionAction(context, event),
                onImageTapped: (event) {
                  debugPrint('[ImageTap] href=${event.href}');
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FullScreenImageView(event: event),
                    ),
                  );
                },
                onDecorationInteraction: (event) => handleDecorationInteraction(context, event),
              ),
            ],
          ),
        );
      }
      // Return a fallback widget in case none of the conditions above are met
      return const ColoredBox(
        color: Color(0xffffff00),
        child: Center(child: Text('Something went wrong.')),
      );
    },
  );
}

/// Handles a selection-menu action. Top-level so the agent extensions can call it without the native view.
/// Returns the new highlight's ID for `highlight`, null otherwise.
String? handleSelectionAction(BuildContext context, SelectionActionEvent event) {
  debugPrint('[SelectionAction] action=${event.actionId} text="${event.selectedText}"');
  if (event.actionId == 'highlight') {
    return _applyHighlight(context, event).decoration.id;
  } else if (event.actionId == 'note') {
    _showNoteDialog(context, event);
  }
  return null;
}

/// Opens the highlight sheet for a tapped highlight. Returns whether the sheet was opened.
bool handleDecorationInteraction(BuildContext context, DecorationInteractionEvent event) {
  debugPrint('[DecorationInteraction] id=${event.decorationId} group=${event.group}');
  final isKnownHighlight =
      event.group == highlightsGroup &&
      context.read<PublicationBloc>().state.highlights.containsKey(event.decorationId);
  if (isKnownHighlight) {
    // PointerInterceptor lets the sheet receive taps over the web platform view.
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => PointerInterceptor(child: HighlightSheet(highlightId: event.decorationId)),
    );
  }
  return isKnownHighlight;
}

// IDs only need to be unique within one app run.
var _nextHighlightId = 0;

Highlight _applyHighlight(BuildContext context, SelectionActionEvent event) {
  final highlight = Highlight(
    decoration: ReaderDecoration(
      id: 'highlight_${_nextHighlightId++}',
      locator: event.locator,
      style: ReaderDecorationStyle(
        style: DecorationStyle.highlight,
        tint: highlightColors['yellow'],
      ),
    ),
    text: event.selectedText ?? event.locator.text?.highlight,
  );
  context.read<PublicationBloc>().add(AddHighlight(highlight));
  debugPrint('[Highlight] Applied highlight decoration');
  return highlight;
}

void _showNoteDialog(BuildContext context, SelectionActionEvent event) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add Note'),
      content: Text('Selected: "${event.selectedText ?? '(no text)'}"'),
      actions: [
        TextButton(
          key: const ValueKey('note_cancel_button'),
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('note_save_button'),
          onPressed: () {
            Navigator.pop(ctx);
            _applyHighlight(context, event);
          },
          child: const Text('Save & Highlight'),
        ),
      ],
    ),
  );
}
