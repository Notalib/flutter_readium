import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart' show FlutterReadium, TextSearchResult;
import 'package:flutter_readium_example/state/index.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String searchQuery = '';
  final List<TextSearchResult> results = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.amber, title: Text('Search')),
      body: StreamBuilder(
        stream: context.read<PublicationBloc>().stream,
        initialData: context.read<PublicationBloc>().state,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data?.publication == null) {
            return Text('No publication');
          } else {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SearchBar(
                    hintText: "Type here...",
                    trailing: [
                      IconButton(
                        onPressed: () {
                          doSearchInPublication(searchQuery);
                        },
                        icon: const Icon(Icons.search),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value;
                      });
                    },
                    onSubmitted: doSearchInPublication,
                  ),
                ),
                SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      return buildSearchResultTile(index, context);
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

  void doSearchInPublication(final String searchQuery) async {
    final searchResults = await FlutterReadium().searchInPublication(searchQuery);
    setState(() {
      results.clear();
      results.addAll(searchResults);
    });
  }

  ListTile buildSearchResultTile(final int index, final BuildContext context) {
    final result = results[index];
    final title = result.chapterTitle ?? "Result $index";
    final subtitle =
        '${result.locator.text?.before} [[[${result.locator.text?.highlight}]]] ${result.locator.text?.after}';
    return ListTile(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 10, overflow: TextOverflow.ellipsis),
      onTap: () {
        debugPrint('Tapped result ${result.chapterTitle}');
        Navigator.pop(context, result);
      },
    );
  }
}
