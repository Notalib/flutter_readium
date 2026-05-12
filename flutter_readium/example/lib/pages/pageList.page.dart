import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart' show Link, PublicationLists;
import 'package:flutter_readium_example/state/index.dart';

class PageListPage extends StatelessWidget {
  const PageListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.blue, title: Text('Page List')),
      body: StreamBuilder(
        stream: context.read<PublicationBloc>().stream,
        initialData: context.read<PublicationBloc>().state,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data?.publication == null) {
            return Text('No publication');
          } else {
            // Note: If no ToC, fallback to readingOrder.
            final pub = snapshot.data!.publication!;
            final links = pub.pageList;
            return ListView.builder(
              itemCount: links.length,
              itemBuilder: (context, idx) {
                final tocLink = links[idx];
                return _buildLinkTile(context, tocLink);
              },
            );
          }
        },
      ),
    );
  }

  Widget _buildLinkTile(BuildContext context, Link link, {int level = 1}) {
    final title = link.title ?? "[NO_TITLE]";
    return ListTile(
      title: Text(title),
      contentPadding: EdgeInsets.only(left: 12.0 * level),
      trailing: Icon(Icons.arrow_forward_ios),
      onTap: () {
        debugPrint('Tapped page: $title: href=${link.href}');
        Navigator.pop(context, link);
      },
    );
  }
}
