import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../state/index.dart';
import 'full_screen_image_view.dart';

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
          child: ReadiumReaderWidget(
            publication: state.publication!,
            initialLocator: state.initialLocator,
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
            onSelectionAction: (event) {
              debugPrint(
                '[SelectionAction] action=${event.actionId} text="${event.selectedText}"',
              );
              if (event.actionId == 'highlight') {
                _applyHighlight(context, event);
              } else if (event.actionId == 'note') {
                _showNoteDialog(context, event);
              }
            },
            onDecorationInteraction: (event) {
              debugPrint(
                '[DecorationInteraction] id=${event.decorationId} group=${event.group}',
              );
              if (event.decorationId.startsWith('highlight')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Tapped highlight: ${event.decorationId}'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            onImageTapped: (event) {
              debugPrint('[ImageTap] href=${event.href} srcUrl=${event.srcUrl}');
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FullScreenImageView(event: event),
                ),
              );
            },
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

  void _applyHighlight(BuildContext context, SelectionActionEvent event) {
    final decoration = ReaderDecoration(
      id: 'highlight_${DateTime.now().millisecondsSinceEpoch}',
      locator: event.locator,
      style: const ReaderDecorationStyle(
        style: DecorationStyle.highlight,
        tint: Color(0x80FFFF00),
      ),
    );
    context.read<PublicationBloc>().add(AddHighlight(decoration));
    debugPrint('[Highlight] Applied highlight decoration');
  }

  void _showNoteDialog(BuildContext context, SelectionActionEvent event) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Note'),
        content: Text('Selected: "${event.selectedText ?? '(no text)'}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
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
}
