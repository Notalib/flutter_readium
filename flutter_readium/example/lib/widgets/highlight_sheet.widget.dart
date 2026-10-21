import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../state/index.dart';

/// Highlight colour palette. All semi-transparent so the text stays readable.
/// Yellow is the default for new highlights.
const highlightColors = <String, Color>{
  'yellow': Color(0x80FFFF00),
  'green': Color(0x8000FF00),
  'blue': Color(0x8000BFFF),
  'pink': Color(0x80FF69B4),
};

/// Bottom sheet for a single highlight: its text, a colour picker and Delete.
class HighlightSheet extends StatelessWidget {
  const HighlightSheet({required this.highlightId, super.key});

  final String highlightId;

  @override
  Widget build(BuildContext context) => BlocSelector<PublicationBloc, PublicationState, Highlight?>(
    selector: (state) => state.highlights[highlightId],
    builder: (context, highlight) {
      // Deleted while the sheet animates out. Delete already popped it, so popping here would close the reader.
      if (highlight == null) return const SizedBox.shrink();
      return SafeArea(
        key: const ValueKey('highlight_sheet'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                highlight.text ?? '(no text)',
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final entry in highlightColors.entries)
                    _ColorSwatch(
                      name: entry.key,
                      color: entry.value,
                      selected: highlight.tint == entry.value,
                      onTap: () => context.read<PublicationBloc>().add(UpdateHighlightColor(highlight.id, entry.value)),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    key: const ValueKey('highlight_delete_button'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    onPressed: () {
                      context.read<PublicationBloc>().add(DeleteHighlight(highlight.id));
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Semantics(
      button: true,
      selected: selected,
      label: name,
      child: Tooltip(
        message: name,
        child: InkResponse(
          key: ValueKey('highlight_color_$name'),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Theme.of(context).colorScheme.primary : Colors.black26,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected ? const Icon(Icons.check, size: 18) : null,
          ),
        ),
      ),
    ),
  );
}
