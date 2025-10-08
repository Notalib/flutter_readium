import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_readium_example/state/index.dart';
import 'package:flutter_readium_example/widgets/index.dart';

class TableOfContentsPage extends StatelessWidget {
  const TableOfContentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Table of Contents')),
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
                    final title = tocLink.title ?? "[NO_TITLE]";
                    return ListTile(
                      title: Text(title),
                      trailing: Icon(Icons.arrow_right),
                      onTap: () {
                        debugPrint('Tapped ${tocLink.title}');
                        Navigator.pop(context, tocLink);
                      },
                    );
                  });
            }
          }),
    );
  }
}
