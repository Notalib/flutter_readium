import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_readium_web/js_publication_channel.dart';
import 'package:flutter_readium_web/readium_webview.dart';

class ReadiumReaderWidget extends StatefulWidget {
  const ReadiumReaderWidget({
    required this.publication,
    this.loadingWidget = const Center(child: CircularProgressIndicator()),
    this.initialLocator,
    this.onTap,
    this.onGoLeft,
    this.onGoRight,
    this.onSwipe,
    super.key,
  });

  final Publication publication;
  final Widget loadingWidget;
  final Locator? initialLocator;
  final VoidCallback? onTap;
  final VoidCallback? onGoLeft;
  final VoidCallback? onGoRight;
  final VoidCallback? onSwipe;

  @override
  State<ReadiumReaderWidget> createState() => _ReadiumReaderWidgetState();
}

class _ReadiumReaderWidgetState extends State<ReadiumReaderWidget> implements ReadiumReaderWidgetInterface {
  @override
  void initState() {
    super.initState();
    R2Log.d('Widget initiated');
  }

  @override
  void dispose() {
    R2Log.d('Widget disposed');
    super.dispose();

    // Close the publication when the widget is disposed
    FlutterReadium().closePublication(
      widget.publication.identifier,
    );
  }

  @override
  Widget build(final BuildContext context) {
    // TODO: move initialPositionJsonString to flutter_readium_web when shared is implemented
    final initialLocator = widget.initialLocator ?? null;
    final initialPositionJsonString = initialLocator != null ? json.encode(widget.initialLocator) : null;
    final publicationUrl = widget.publication.links
        .firstWhereOrNull(
          (final link) => link.href.contains('manifest.json'),
        )
        ?.href;
    if (publicationUrl == null) {
      return Center(
        child: Text('Publication URL not found.'),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 1500),
        child: SizedBox.expand(
          child: ReadiumWebView(
            publicationURL: publicationUrl,
            currentLocatorString: initialPositionJsonString,
          ),
        ),
      ),
    );
  }

  @override
  Future<void> go(
    final Locator locator, {
    required final bool isAudioBookWithText,
    final bool animated = false,
  }) async {
    try {
      await JsPublicationChannel.goToLocation(locator.hrefPath);
    } on PlatformException catch (e, stackTrace) {
      final pubID = widget.publication.metadata.identifier;
      throw ReadiumError(
        'Error when navigating to locator: ${e.message}',
        code: e.code,
        data: 'publication id: $pubID. locator: $locator',
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> goLeft({final bool animated = true}) async {
    JsPublicationChannel.goLeft();
  }

  @override
  Future<void> goRight({final bool animated = true}) async {
    JsPublicationChannel.goRight();
  }

  @override
  // ignore: prefer_expression_function_bodies
  Future<Locator?> getLocatorFragments(final Locator locator) async {
    // Implement this method if needed
    return null;
  }

  @override
  Future<void> skipToPrevious({final bool animated = true}) async {
    R2Log.d('skipToPrevious not implemented in web version');
  }

  @override
  Future<void> skipToNext({final bool animated = true}) async {
    R2Log.d('skipToNext not implemented in web version');
  }

  @override
  Future<Locator?> getCurrentLocator() async {
    R2Log.d('getCurrentLocator not implemented in web version');
    return null;
  }

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    R2Log.d('setEPUBPreferences not implemented in web version');
  }

  @override
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async {
    R2Log.d('applyDecorations not implemented in web version');
  }

  @override
  Future<void> ttsStart(String langCode, Locator? fromLocator) async {
    R2Log.d('ttsStart not implemented in web version');
  }

  @override
  Future<void> ttsStop() async {
    R2Log.d('ttsStop not implemented in web version');
  }
}
