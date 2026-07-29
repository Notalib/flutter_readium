import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:logging/logging.dart';

import '../state/index.dart';
import '../utils/index.dart';

final _log = Logger('BookshelfPage');

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
      final String response = await rootBundle.loadString(
        'assets/webManifestList.json',
      );
      final List<dynamic> manifestHrefs = json.decode(response);
      for (final href in manifestHrefs) {
        try {
          Publication? pub;
          final rawHref = href.toString();
          // WEB: Resolve root-relative paths against the current origin, so local files can be loaded.
          final localPubPath = rawHref.startsWith('/') ? Uri.base.resolve(rawHref).toString() : rawHref;
          pub = await loadPublicationFromUrl(localPubPath);
          if (pub != null) {
            loadedPublications.add(pub);
            loadedPublicationURLs.add(localPubPath);
          }
        } on Exception catch (e) {
          _log.severe('Error opening publication: $e');
        }
      }
    } else {
      // should only be done first time app is started. how to do that?
      final localPublications = await PublicationUtils.moveAssetPublicationsToReadiumStorage();

      for (String localPubPath in localPublications) {
        _log.info('Loading publication from local path: $localPubPath');
        final publication = await loadPublicationFromUrl(localPubPath);
        if (publication != null) {
          loadedPublications.add(publication);
          loadedPublicationURLs.add(localPubPath);
        } else {
          _log.warning('Failed to load publication from path: $localPubPath');
        }
      }
    }

    // Set a custom header for all publication requests (e.g., for authentication).
    _flutterReadiumPlugin.setCustomHeaders({
      'X-Custom-Header': 'MyCustomValue',
    });

    final publicationEntries =
        List.generate(
          loadedPublications.length,
          (index) => (publication: loadedPublications[index], url: loadedPublicationURLs[index]),
        )..sort((left, right) {
          final formatComparison = _bookFormatSortOrder(
            left.publication,
          ).compareTo(_bookFormatSortOrder(right.publication));
          if (formatComparison != 0) {
            return formatComparison;
          }

          return left.publication.metadata.title.compareTo(
            right.publication.metadata.title,
          );
        });

    setState(() {
      _testPublications = publicationEntries.map((entry) => entry.publication).toList();
      _testPublicationURLs = publicationEntries.map((entry) => entry.url).toList();
      _isLoading = false;
    });
  }

  Future<Publication?> loadPublicationFromUrl(String pubUrl) async {
    try {
      Publication pub = await _flutterReadiumPlugin.loadPublication(pubUrl);
      _log.info('loadPublication success: ${pub.metadata.title}');
      return pub;
    } on PlatformException catch (e) {
      _log.warning('Failed to open publication: ${e.message}');
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
                        return _buildPubCard(
                          publication,
                          publicationUrl,
                          context,
                        );
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
  void _toast(
    final String text, {
    final Duration duration = const Duration(milliseconds: 4000),
  }) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), duration: duration));
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
  //     ReadiumLog.d('Picked file: ${file.path}');

  //     return await PublicationUtils.copyFileToReadiumPubStorage(file);
  //   } else {
  //     ReadiumLog.d('User canceled the picker');
  //     return null;
  //   }
  // }

  String _bookFormatFromConformsTo(Publication pub) {
    if (pub.conformsToReadiumEbook) {
      if (pub.isAudioBook) {
        return 'Ebook with audio';
      }
      return 'Ebook';
    } else if (pub.conformsToReadiumAudiobook) {
      return 'Audiobook';
    } else if (pub.conformsToReadiumPDF) {
      return 'PDF';
    } else if (pub.conformsToReadiumDivina) {
      return 'Comic';
    } else {
      return 'Unknown format';
    }
  }

  int _bookFormatSortOrder(Publication pub) {
    if (pub.conformsToReadiumEbook) {
      if (pub.isAudioBook) {
        return 1;
      }
      return 0;
    } else if (pub.conformsToReadiumAudiobook) {
      return 2;
    } else if (pub.conformsToReadiumPDF) {
      return 3;
    } else if (pub.conformsToReadiumDivina) {
      return 4;
    } else {
      return 5;
    }
  }

  Widget _buildPubCard(
    final Publication publication,
    String publicationUrl,
    final BuildContext context,
  ) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 4.0),
    child: InkWell(
      key: ValueKey('book_card_${sanitizeForKey(publication.metadata.title)}'),
      onTap: () {
        // Use an in-memory saved locator as initial locator when opening the publication,
        // so that we can restore the last reading position.
        // This is just for demo purposes, in a real app you would probably want to persist the locator.
        final pubUrlHashCode = publicationUrl.hashCode.toString();
        final savedInitialLocator = savedLocators[pubUrlHashCode];

        try {
          context.read<PublicationBloc>().add(
            OpenPublication(
              publicationUrl: publicationUrl,
              initialLocator: savedInitialLocator,
            ),
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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      publication.metadata.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _listAuthors(publication),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _bookFormatFromConformsTo(publication),
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'File: ${publicationUrl.split('/').last}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // remove the if when books loaded from asset can be deleted
              if (!kIsWeb && !_identifiersFromAsset.contains(publication.identifier))
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    try {
                      PublicationUtils.removePublicationFromReadiumStorage(
                        publication.identifier,
                      );
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
  //             ReadiumLog.e('error picking file: $e');
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
