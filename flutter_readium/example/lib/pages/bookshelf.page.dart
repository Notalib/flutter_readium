import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../state/index.dart';
import '../utils/index.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  BookshelfPageState createState() => BookshelfPageState();
}

class BookshelfPageState extends State<BookshelfPage> {
  final _flutterReadiumPlugin = FlutterReadium();
  final ScrollController _scrollController = ScrollController();
  List<Publication> _testPublications = [];
  List<String> _testPublicationURLs = [];
  bool _isLoading = true;
  // Pubs loaded from assets folder should not be delete-able as they would just be re-added on restart
  // we should probably make it so they will only be loaded once
  final List<String> _identifiersFromAsset = ['dk-nota-714304'];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final loadedPublications = <Publication>[];
    final loadedPublicationURLs = <String>[];

    if (kIsWeb) {
      // Web: Load publications from JSON asset
      final String response = await rootBundle.loadString('assets/webManifestList.json');
      final List<dynamic> manifestHrefs = json.decode(response);
      for (final href in manifestHrefs) {
        try {
          Publication? pub;
          final localPubPath = href.toString();
          pub = await loadPublicationFromUrl(localPubPath);
          if (pub != null) {
            loadedPublications.add(pub);
            loadedPublicationURLs.add(localPubPath);
          }
        } on Exception catch (e) {
          debugPrint('Error opening publication: $e');
        }
      }
    } else {
      // should only be done first time app is started. how to do that?
      final localPublications = await PublicationUtils.moveAssetPublicationsToReadiumStorage();

      for (String localPubPath in localPublications) {
        debugPrint('Loading publication from local path: $localPubPath');
        final publication = await loadPublicationFromUrl(localPubPath);
        if (publication != null) {
          loadedPublications.add(publication);
          loadedPublicationURLs.add(localPubPath);
        } else {
          debugPrint('Failed to load publication from path: $localPubPath');
        }
      }
    }

    // Set a custom header for all publication requests (e.g., for authentication).
    _flutterReadiumPlugin.setCustomHeaders({
      'X-Custom-Header': 'MyCustomValue',
      // 'Authorization':
      //     'Bearer eyJhbGciOiJSUzI1NiIsImtpZCI6IjhERUM4MDk4N0UwMzVCRjMwOUVGNUM2NEY5RjlEMUZGM0Q2MTQ3RjZSUzI1NiIsIng1dCI6ImpleUFtSDREV19NSjcxeGstZm5SX3oxaFJfWSIsInR5cCI6ImF0K2p3dCJ9.eyJpc3MiOiJodHRwczovL2F1dGgtYmV0YS5ub3RhLmRrIiwibmJmIjoxNzcxMzQ0ODUwLCJpYXQiOjE3NzEzNDQ4NTAsImV4cCI6MTc3MTM0ODQ1MCwiYXVkIjoibm90YV9hcGkiLCJzY29wZSI6WyJvcGVuaWQiLCJwcm9maWxlIiwibm90YSIsIm5vdGFfYXBpIiwib2ZmbGluZV9hY2Nlc3MiXSwiYW1yIjpbInB3ZCJdLCJjbGllbnRfaWQiOiI5ODMwZjg2Zi1kMmQ3LTRkMTAtOTc3Yy1mNGRlMDI0NjEwOGUiLCJzdWIiOiIxMDE0MDM0NSIsImF1dGhfdGltZSI6MTc3MTMzOTg2MywiaWRwIjoibG9jYWwiLCJwZXJtaXNzaW9uIjpbIkJyYWlsbGVCayIsIkVCb29rQ2QiLCJCck11c2ljIiwiRUJvb2tEbyIsIlRhbGtCa0RvIiwiVGFsa0JrQ2QiLCJNYW5lbm8iLCJFZHVCb29rUHJvdGVjdGVkRG8iLCJQYXBlckZvckJsaW5kRG8iXSwibWVtYmVyVHlwZSI6IkVNUExPWUVFIiwiZW1haWwiOiJkZmdAbm90YS5kayIsInNpZCI6IjkxODY3RThGODQ1QjBBRjRGMzgyMkU3QTYwMjdBNDBBIiwianRpIjoiNUUyNkZCRTA0OUZEQkY0NDJCQ0Y4RDIxQzUzN0NEQjYifQ.uI3-hoQWFrR37QXnJWKWihMXsOIXkwv4EDpJsWwjLLnDKLNBLoY8H3cTcMYiYkE9c9WmEWs5RTI2wejUCBmutJqAtuctgS-GiiI8x9p1shDAAXCJqo9mnldFNHtXC-Viitfn6Ln1azGj2gHEtBh5AoPVSReAgrRh5QphDV51xu2watCUNs5FaL1HuV1oAshms6CY1v01xzta5us7tu4Yds3tVsQPom1GOoJE30VkfeOZhgyatQgSvFn6RZr4FLnHMztWzI7LmpV3clZmamQtPBZTMijBVBr_uPj73N_J-GLAQEpq0lqlwwZHyhZpxQ9CYqqFHWWP3OfcnFjS3Fb5PBsZ7g0Sy8N4rGH9J_xULLuomXkUBSX059Bjg2cWEKnY4YClIcb-u6Sgz6gyvqwB3VBWybM3Yu3CaCfLizrQHYvROGHawpp_BcoELwZ-rRkLLHs7BirLZMO7HGD667fgsnBbieBkDXACVU7lxRGxrLHDygJ6oFFlj-2HxpUrM5v-l5acz6JMWmwp4xcHj8mUTEyLFDrmFxYNBNqE6XVeTTD0CeG_phDt0J8Rm2yyUUjnmE3eyq-sX4iuU7LXSp4WZ6wZ10iBklUb_FDXwRlSr8cH0gqQVMH1UBB1YKeJypkpp2cmnYXB-huB4LF6zWQh6-ZYwsdcAtVIbXpt2es-akQ',
    });

    // Load a streaming audiobook publication from URL.
    // final audioBookUrl =
    //     'https://merkur-test.azurewebsites.net/opds2/mtmstreamer/publication/merkur:libraryid:CA61812/manifest.json?format=WebPubAudioOnly&absoluteUrls=true';
    // final testStreamingAudioBook = await loadPublicationFromUrl(audioBookUrl);
    // if (testStreamingAudioBook != null) {
    //   loadedPublications.add(testStreamingAudioBook);
    //   loadedPublicationURLs.add(audioBookUrl);
    // }

    setState(() {
      _testPublications = loadedPublications;
      _testPublicationURLs = loadedPublicationURLs;
      _isLoading = false;
    });
  }

  Future<Publication?> loadPublicationFromUrl(String pubUrl) async {
    try {
      Publication pub = await _flutterReadiumPlugin.loadPublication(pubUrl);
      debugPrint('loadPublication success: ${pub.metadata.title}');
      return pub;
    } on PlatformException catch (e) {
      debugPrint('Failed to open publication: ${e.message}');
      return null;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) => Scaffold(
    restorationId: 'bookshelf_page',
    appBar: AppBar(title: Text('Example Bookshelf')),
    body: SafeArea(
      child: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: CupertinoScrollbar(
                    controller: _scrollController,
                    thickness: 5.0,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: _testPublications.length,
                      itemBuilder: (final context, final index) {
                        final publication = _testPublications[index];
                        final publicationUrl = _testPublicationURLs[index];
                        return _buildPubCard(publication, publicationUrl, context);
                      },
                    ),
                  ),
                ),
                // Divider(),
                // _buildAddBookCard(context),
              ],
            ),
    ),
  );

  // ignore: unused_element
  void _toast(final String text, {final Duration duration = const Duration(milliseconds: 4000)}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: duration));
  }

  String _listAuthors(final Publication pub) {
    final metadata = pub.metadata;
    final authors = metadata.authors;

    final authorNames = authors.map((final author) => author.localizedName?.string).nonNulls.join(', ');

    return authorNames.isEmpty ? 'Unknown author' : authorNames;
  }

  // Future<String?> _pickAndImportPubFromFile() async {
  //   final result = await FilePicker.platform.pickFiles();

  //   if (result != null) {
  //     final platformFile = result.files.first;

  //     // Convert PlatformFile to File
  //     final file = File(platformFile.path!);

  //     // Validate the file
  //     // PublicationUtils.validateFile(file);
  //     R2Log.d('Picked file: ${file.path}');

  //     return await PublicationUtils.copyFileToReadiumPubStorage(file);
  //   } else {
  //     R2Log.d('User canceled the picker');
  //     return null;
  //   }
  // }

  String _bookFormatFromConformsTo(Publication pub) {
    if (pub.conformsToReadiumEbook) {
      return 'Ebook';
    } else if (pub.conformsToReadiumAudiobook) {
      return 'Audiobook';
    } else {
      return 'Unknown format';
    }
  }

  Widget _buildPubCard(final Publication publication, String publicationUrl, final BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 4.0),
    child: InkWell(
      onTap: () {
        // Use an in-memory saved locator as initial locator when opening the publication,
        // so that we can restore the last reading position.
        // This is just for demo purposes, in a real app you would probably want to persist the locator.
        final savedInitialLocator = savedLocators[publication.identifier];

        try {
          context.read<PublicationBloc>().add(
            OpenPublication(publicationUrl: publicationUrl, initialLocator: savedInitialLocator),
          );

          Navigator.restorablePushNamed(context, '/player');
        } on Object catch (e) {
          _toast('Error opening publication: $e');
        }
      },
      child: Card(
        color: Colors.blue[100],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 15.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(publication.metadata.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(_listAuthors(publication)),
                  Text(_bookFormatFromConformsTo(publication)),
                  Text(publicationUrl.split('/').last),
                ],
              ),
              // remove the if when books loaded from asset can be deleted
              if (!_identifiersFromAsset.contains(publication.identifier))
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    try {
                      PublicationUtils.removePublicationFromReadiumStorage(publication.identifier);
                      setState(() {
                        _testPublications.remove(publication);
                      });
                    } on Object catch (e) {
                      _toast('Error deleting publication: $e');
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );

  // Widget _buildAddBookCard(final BuildContext context) => Container(
  //       padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 4.0),
  //       child: InkWell(
  //         onTap: () async {
  //           try {
  //             String? importedPubPath = await _pickAndImportPubFromFile();
  //             if (importedPubPath == null) return;
  //             Publication? importedPublication = await openPublicationFromUrl(importedPubPath);
  //             if (importedPublication != null) {
  //               setState(() {
  //                 _testPublications.add(importedPublication);
  //               });
  //             }
  //           } on Object catch (e) {
  //             R2Log.e('error picking file: $e');
  //             _toast('Error picking file $e');
  //           }
  //         },
  //         child: Card(
  //           color: Colors.blue[200],
  //           child: Padding(
  //             padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 5.0),
  //             child: Row(
  //               mainAxisAlignment: MainAxisAlignment.center,
  //               children: [
  //                 Icon(Icons.add, size: 30, color: Colors.blue),
  //                 Text(
  //                   'Add Book',
  //                   style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
  //                 ),
  //               ],
  //             ),
  //           ),
  //         ),
  //       ),
  //     );
}
