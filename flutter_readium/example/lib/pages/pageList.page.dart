import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: _PageAutocomplete(links: links),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: links.length,
                    itemBuilder: (context, idx) {
                      final itemLink = links[idx];
                      return _buildLinkTile(context, itemLink);
                    },
                  ),
                ),
              ],
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

class _PageAutocomplete extends StatelessWidget {
  const _PageAutocomplete({required this.links});

  final List<Link> links;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Link>(
      displayStringForOption: (link) => link.title ?? '',
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim();
        if (query.isEmpty) return const Iterable.empty();
        return links.where((link) {
          final pageNum = link.title?.replaceFirst('Page ', '') ?? '';
          return pageNum.startsWith(query);
        });
      },
      optionsMaxHeight: 200,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          key: const ValueKey('page_autocomplete_field'),
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'Go to page...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      onSelected: (link) {
        _log.info('Selected page: ${link.title}: href=${link.href}');
        Navigator.pop(context, link);
      },
    );
  }
}
