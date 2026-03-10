import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'src/index.dart';

class ReadiumReaderWidget extends StatefulWidget {
  const ReadiumReaderWidget({
    required this.publication,
    this.loadingWidget = const Center(child: CircularProgressIndicator()),
    this.initialLocator,
    this.shouldShowControls,
    this.onExternalLinkActivated,
    super.key,
  });

  final Publication publication;
  final Widget loadingWidget;
  final Locator? initialLocator;
  final ValueNotifier<bool>? shouldShowControls;
  final Function(String)? onExternalLinkActivated;

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
    FlutterReadium().closePublication();
  }

  @override
  Widget build(final BuildContext context) {
    return SizedBox.expand(
      child: ReadiumWebView(publication: widget.publication, currentLocator: widget.initialLocator),
    );
  }

  @override
  Future<void> go(final Locator locator, {required final bool isAudioBookWithText, final bool animated = false}) async {
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
  Future<void> skipToPrevious({final bool animated = true}) async {
    R2Log.d('skipToPrevious not implemented in web version');
  }

  @override
  Future<void> skipToNext({final bool animated = true}) async {
    R2Log.d('skipToNext not implemented in web version');
  }

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    R2Log.d('setEPUBPreferences not implemented in web version');
  }

  @override
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async {
    R2Log.d('applyDecorations not implemented in web version');
  }
}
