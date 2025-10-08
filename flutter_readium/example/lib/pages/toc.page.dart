import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart' show Link;
import 'package:flutter_readium_example/state/index.dart';

import 'dart:math' show min, max;

class TableOfContentsPage extends StatelessWidget {
  const TableOfContentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.amber,
        title: Text('Table of Contents'),
      ),
      body: StreamBuilder(
          stream: context.read<PublicationBloc>().stream,
          initialData: context.read<PublicationBloc>().state,
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data?.publication == null) {
              return Text('No publication');
            } else {
              // Note: If no ToC, fallback to readingOrder.
              final pub = snapshot.data!.publication!;
              final links = pub.toc ?? pub.readingOrder;
              return ListView.builder(
                  itemCount: links.length,
                  itemBuilder: (context, idx) {
                    final tocLink = links[idx];
                    return _buildLinkTile(context, tocLink);
                  });
            }
          }),
    );
  }

  Widget _buildLinkTile(BuildContext context, Link link, {int level = 1}) {
    final title = link.title ?? "[NO_TITLE]";
    if ((link.children?.length ?? 0) > 1) {
      final children = link.children!;
      return ExpansionTile(
        title: Text(title),
        controlAffinity: ListTileControlAffinity.leading,
        backgroundColor: Colors.blue[min(max(level * 100, 0), 900)],
        initiallyExpanded: true,
        children: children.map((c) => _buildLinkTile(context, c, level: level + 1)).toList(),
      );
    } else {
      return ListTile(
        title: Text(title),
        contentPadding: EdgeInsets.only(left: 12.0 * level),
        trailing: Icon(Icons.arrow_forward_ios),
        onTap: () {
          debugPrint('Tapped $title');
          Navigator.pop(context, link);
        },
      );
    }
  }
}
