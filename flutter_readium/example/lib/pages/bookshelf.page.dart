import 'dart:async';
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
  // URLs of publications picked from the device; opened in place (never copied
  // into app storage) and persisted across restarts by PickedBooksStore.
  final Set<String> _pickedUrls = {};

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final loadedPublications = <Publication>[];
    final loadedPublicationURLs = <String>[];
    try {
      if (kIsWeb) {
        // Web: Load publications from JSON asset
        final String response = await rootBundle.loadString(
          'assets/webManifestList.json',
        );
        final List<dynamic> manifestHrefs = json.decode(response);
        for (final href in manifestHrefs) {
          try {
            final rawHref = href.toString();
            // WEB: Resolve root-relative paths against the current origin, so local files can be loaded.
            final localPubPath = rawHref.startsWith('/') ? Uri.base.resolve(rawHref).toString() : rawHref;
            final pub = await loadPublicationFromUrl(localPubPath);
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

        for (final localPubPath in localPublications) {
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

      // Publications picked from the device: opened in place (never copied
      // into app storage), URLs persisted across restarts. iOS hands the
      // picker's temp copy back to the OS, so entries that vanished are
      // dropped from the store.
      if (!kIsWeb) {
        final storedUrls = await PickedBooksStore.load();
        final stillAvailable = <String>[];
        for (final url in storedUrls) {
          if (await DeviceFileImporter.isStillAvailable(url)) {
            stillAvailable.add(url);
          } else {
            _log.info('Dropping picked publication, no longer available: $url');
            await PickedBooksStore.remove(url);
          }
        }
        for (final url in stillAvailable) {
          final publication = await loadPublicationFromUrl(url);
          if (publication != null) {
            loadedPublications.add(publication);
            loadedPublicationURLs.add(url);
            _pickedUrls.add(url);
          } else {
            _log.warning('Failed to load picked publication from url: $url');
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

      if (!mounted) {
        return;
      }

      setState(() {
        _testPublications = publicationEntries.map((entry) => entry.publication).toList();
        _testPublicationURLs = publicationEntries.map((entry) => entry.url).toList();
      });
    } on Exception catch (e, stackTrace) {
      _log.severe('Bookshelf initialization failed: $e', e, stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<Publication?> loadPublicationFromUrl(String pubUrl) async {
    try {
      final Publication pub = await _flutterReadiumPlugin.loadPublication(pubUrl).timeout(const Duration(seconds: 20));
      _log.info('loadPublication success: ${pub.metadata.title}');
      return pub;
    } on TimeoutException {
      _log.warning('Timed out loading publication: $pubUrl');
      return null;
    } on ReadiumException catch (e) {
      _log.warning('Failed to open publication [$pubUrl]: ${e.code} ${e.message}');
      return null;
    } on PlatformException catch (e) {
      _log.warning('Failed to open publication: ${e.message}');
      return null;
    } on Exception catch (e) {
      _log.warning('Unexpected publication load error for [$pubUrl]: $e');
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
                  child: _testPublications.isEmpty
                      ? _buildEmptyState(context)
                      : CupertinoScrollbar(
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
                if (!kIsWeb) _buildAddBookCard(context),
              ],
            ),
    ),
  );

  /// Test fixtures are generated and gitignored, so an empty shelf almost always
  /// means `bin/fetch_test_resources` has not been run in this checkout.
  Widget _buildEmptyState(final BuildContext context) => Center(
    key: const ValueKey('bookshelf_empty_state'),
    child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('No publications found', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Test fixtures are generated, not committed. Run bin/fetch_test_resources '
            'from the repo root, then restart the app.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
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

  /// Opens the OS file picker and, on success, adds the picked publication to
  /// the shelf in place (no copy into app storage) and persists its URL.
  Future<void> _pickAndAddPublication() async {
    try {
      final url = await DeviceFileImporter.pickPublicationUrl();
      if (url == null) return; // User canceled.
      if (_pickedUrls.contains(url)) {
        _toast('Publication is already on the bookshelf');
        return;
      }
      final publication = await loadPublicationFromUrl(url);
      if (publication == null) {
        _toast('Could not open the selected file as a publication');
        return;
      }
      await PickedBooksStore.add(url);
      if (!mounted) return;
      setState(() {
        _pickedUrls.add(url);
        _testPublications = [..._testPublications, publication];
        _testPublicationURLs = [..._testPublicationURLs, url];
        _sortPublicationsInPlace();
      });
    } on UnsupportedFormatException catch (e) {
      _toast(e.toString());
    } on Object catch (e) {
      _log.severe('Error picking publication: $e');
      _toast('Error picking file: $e');
    }
  }

  void _sortPublicationsInPlace() {
    final indices = List.generate(_testPublications.length, (i) => i)
      ..sort((left, right) {
        final formatComparison = _bookFormatSortOrder(
          _testPublications[left],
        ).compareTo(_bookFormatSortOrder(_testPublications[right]));
        if (formatComparison != 0) return formatComparison;
        return _testPublications[left].metadata.title.compareTo(
          _testPublications[right].metadata.title,
        );
      });
    _testPublications = indices.map((i) => _testPublications[i]).toList();
    _testPublicationURLs = indices.map((i) => _testPublicationURLs[i]).toList();
  }

  void _removePublication(Publication publication, String url) {
    final index = _testPublicationURLs.indexOf(url);
    if (index != -1) {
      _testPublications = [..._testPublications]..removeAt(index);
      _testPublicationURLs = [..._testPublicationURLs]..removeAt(index);
    } else {
      _testPublications = [..._testPublications]..remove(publication);
    }
  }

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
          context.read<PlayerControlsBloc>().resetCurrentLocator();
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
                  key: ValueKey('delete_book_${sanitizeForKey(publicationUrl.split('/').last)}'),
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    try {
                      if (_pickedUrls.contains(publicationUrl)) {
                        // Picked books live outside app storage: only forget
                        // the URL, never delete the user's file.
                        await PickedBooksStore.remove(publicationUrl);
                        if (!mounted) return;
                        setState(() {
                          _pickedUrls.remove(publicationUrl);
                          _removePublication(publication, publicationUrl);
                        });
                        return;
                      }
                      await PublicationUtils.removePublicationFromReadiumStorage(
                        publication.identifier,
                      );
                      setState(() {
                        _removePublication(publication, publicationUrl);
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
      key: const ValueKey('add_book_card'),
      onTap: _pickAndAddPublication,
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
