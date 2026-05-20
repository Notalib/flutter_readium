import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart' show Link, PublicationLists;
import 'package:flutter_readium_example/state/index.dart';
import 'package:logging/logging.dart';

final _log = Logger('PageListPage');

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
            final pub = snapshot.data!.publication!;
            final links = pub.pageListOrGenerated;
            return ListView.builder(
              itemCount: links.length,
              itemBuilder: (context, idx) {
                final itemLink = links[idx];
                return _buildLinkTile(context, itemLink);
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
        _log.info('Tapped page: $title: href=${link.href}');
        Navigator.pop(context, link);
      },
    );
  }
}
