import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium_example/state/index.dart';

class HighlightsPage extends StatelessWidget {
  const HighlightsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.amber,
      title: const Text('Highlights'),
    ),
    body: BlocBuilder<PublicationBloc, PublicationState>(
      builder: (context, state) {
        final highlights = state.highlightsInReadingOrder;
        if (highlights.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No highlights yet. Select text and choose Highlight.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          key: const ValueKey('highlights_list'),
          itemCount: highlights.length,
          itemBuilder: (context, idx) {
            final highlight = highlights[idx];
            return ListTile(
              key: ValueKey('highlight_row_${highlight.id}'),
              leading: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: highlight.tint, shape: BoxShape.circle),
              ),
              title: Text(
                highlight.text ?? '(no text)',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                key: ValueKey('highlight_delete_${highlight.id}'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete highlight',
                onPressed: () => context.read<PublicationBloc>().add(DeleteHighlight(highlight.id)),
              ),
              onTap: () => Navigator.pop(context, highlight.decoration.locator),
            );
          },
        );
      },
    ),
  );
}
