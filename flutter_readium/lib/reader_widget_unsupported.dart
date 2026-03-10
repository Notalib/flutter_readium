import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

class ReadiumReaderWidget extends StatelessWidget {
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
  Widget build(final BuildContext context) => Center(child: Text('ReaderWidget is not available on this platform.'));
}
