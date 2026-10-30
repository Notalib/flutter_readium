import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../state/index.dart';
import 'full_screen_image_view.dart';

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

class ReaderWidget extends StatefulWidget {
  const ReaderWidget({this.shouldShowControls, super.key});

  final ValueNotifier<bool>? shouldShowControls;

  @override
  State<ReaderWidget> createState() => _ReaderWidgetState();
}

class _ReaderWidgetState extends State<ReaderWidget> {
  /// Reader positions to return to after the reader followed an internal link.
  final _returnStack = ValueNotifier<List<Locator>>(const []);

  @override
  void dispose() {
    _returnStack.dispose();
    super.dispose();
  }

  @override
  Widget build(
    final BuildContext context,
  ) => BlocListener<PublicationBloc, PublicationState>(
    listenWhen: (prev, next) => prev.publication != next.publication,
    listener: (_, _) => _returnStack.value = const [],
    child: BlocBuilder<PublicationBloc, PublicationState>(
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
                  shouldShowControls: widget.shouldShowControls,
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
                  onImageTapped: (event) {
                    debugPrint('[ImageTap] href=${event.href}');
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FullScreenImageView(event: event),
                      ),
                    );
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
                  onInternalLinkActivated: (event) {
                    debugPrint('[InternalLink] from=${event.from?.href} target=${event.target.href}');
                    final from = event.from;
                    if (from != null) {
                      _returnStack.value = [..._returnStack.value, from];
                    }
                  },
                ),
                Positioned(
                  // Top, because the player controls overlay the bottom of the reader.
                  left: 16,
                  top: 16,
                  child: ValueListenableBuilder<List<Locator>>(
                    valueListenable: _returnStack,
                    builder: (context, stack, _) {
                      if (stack.isEmpty) return SizedBox.shrink();
                      return FloatingActionButton.extended(
                        key: const ValueKey('return_to_previous_position_button'),
                        heroTag: null,
                        icon: const Icon(Icons.undo),
                        label: const Text('Return to previous position'),
                        onPressed: () {
                          final locator = stack.last;
                          _returnStack.value = stack.sublist(0, stack.length - 1);
                          FlutterReadium().goToLocator(locator);
                        },
                      );
                    },
                  ),
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
    ),
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
}
