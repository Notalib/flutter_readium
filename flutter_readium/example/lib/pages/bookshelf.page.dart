import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
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
  List<Publication> _testPublications = [];
  bool _isLoading = true;
  // Pubs loaded from assets folder should not be delete-able as they would just be re-added on restart
  // we should probably make it so they will only be loaded once
  final List<String> _identifiersFromAsset = ['dk-nota-714304'];

  // TODO: find a better solution for initialLocator.
  final initialLocator = Locator(
    href: '/OPS/main2.xml',
    title: 'Test',
    // locations: Locations(cssSelector: '#chapter_245810 > div > p:nth-child(19)'),
    locations: Locations(
      progression: 0.38461538461538464,
      position: 26,
      totalProgression: 0.176056338028169,
    ),
    type: 'text/html',
  );

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // should only be done first time app is started. how to do that?
    final localPublications = await PublicationUtils.moveAssetPublicationsToReadiumStorage();
    final loadedPublications = <Publication>[];

    for (String localPubPath in localPublications) {
      Publication? publication = await openPublicationFromUrl(localPubPath);
      if (publication != null) {
        loadedPublications.add(publication);
      }
    }

    setState(() {
      _testPublications = loadedPublications;
      _isLoading = false;
    });
  }

  Future<Publication?> openPublicationFromUrl(String pubUrl) async {
    try {
      Publication pub = await _flutterReadiumPlugin.openPublication(pubUrl);
      debugPrint('openPublication success: ${pub.metadata.title}');
      return pub;
    } on PlatformException catch (e) {
      debugPrint('Failed to open publication: ${e.message}');
      return null;
    }
  }

  @override
  Widget build(final BuildContext context) => Scaffold(
        restorationId: 'bookshelf_page',
        appBar: AppBar(
          backgroundColor: Colors.deepPurple[200],
          title: Text('Bookshelf'),
        ),
        body: SafeArea(
          child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: CupertinoScrollbar(
                        thickness: 5.0,
                        thumbVisibility: true,
                        child: ListView.builder(
                          itemCount: _testPublications.length,
                          itemBuilder: (final context, final index) {
                            final publication = _testPublications[index];
                            return _buildPubCard(publication, context);
                          },
                        ),
                      ),
                    ),
                    Divider(),
                    _buildAddBookCard(context),
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
    final authors = metadata.author;

    final authorNames = authors?.map((final author) => author.name.values.first).join(', ');

    return authorNames ?? 'Unknown author';
  }

  Future<String?> _pickAndImportPubFromFile() async {
    final result = await FilePicker.platform.pickFiles();

    if (result != null) {
      final platformFile = result.files.first;

      // Convert PlatformFile to File
      final file = File(platformFile.path!);

      // Validate the file
      // PublicationUtils.validateFile(file);
      R2Log.d('Picked file: ${file.path}');

      return await PublicationUtils.copyFileToReadiumPubStorage(file);
    } else {
      R2Log.d('User canceled the picker');
      return null;
    }
  }

  Widget _buildPubCard(final Publication publication, final BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 4.0),
        child: InkWell(
          onTap: () {
            final fakeInitialLocator = publication.locatorFromLink(publication.readingOrder[2]);
            try {
              context
                  .read<PublicationBloc>()
                  .add(OpenPublication(publication: publication, initialLocator: fakeInitialLocator));
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
                      Text(
                        publication.metadata.title.values.first,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      Text(_listAuthors(publication)),
                      Text(publication.metadata.xIsAudiobook ? 'Audiobook' : 'Ebook'),
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

  Widget _buildAddBookCard(final BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 4.0),
        child: InkWell(
          onTap: () async {
            try {
              String? importedPubPath = await _pickAndImportPubFromFile();
              if (importedPubPath == null) return;
              Publication? importedPublication = await openPublicationFromUrl(importedPubPath);
              if (importedPublication != null) {
                setState(() {
                  _testPublications.add(importedPublication);
                });
              }
            } on Object catch (e) {
              R2Log.e('error picking file: $e');
              _toast('Error picking file $e');
            }
          },
          child: Card(
            color: Colors.blue[200],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 5.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 30, color: Colors.blue),
                  Text(
                    'Add Book',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
