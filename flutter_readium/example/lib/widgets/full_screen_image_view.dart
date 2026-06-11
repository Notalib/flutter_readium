import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

/// Full-screen pinch-zoom image viewer shown when the user taps an image in
/// an EPUB.
///
/// On Web, the image is loaded directly via `Image.network` using
/// [ImageTapEvent.srcUrl] (no byte-bridge round-trip). On iOS (and future
/// Android), the bytes are fetched via [FlutterReadium.getResourceBytes] and
/// displayed with `Image.memory`.
///
/// Dismiss by tapping the background or pressing the system back button.
class FullScreenImageView extends StatelessWidget {
  const FullScreenImageView({required this.event, super.key});

  final ImageTapEvent event;

  @override
  Widget build(BuildContext context) {
    final srcUrl = event.srcUrl;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  key: const ValueKey<String>('full_screen_image_gesture'),
                  minScale: 0.5,
                  maxScale: 10.0,
                  child: _buildImage(context, srcUrl),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context, String? srcUrl) {
    // Web: prefer the served URL — no byte bridge needed.
    if (srcUrl != null && srcUrl.isNotEmpty) {
      return Image.network(
        key: const ValueKey<String>('full_screen_image_network'),
        srcUrl,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _loadingSpinner();
        },
        errorBuilder: (context, error, stackTrace) => _errorWidget(error),
      );
    }

    // iOS / Android: fetch bytes via the resource bridge.
    return FutureBuilder<List<int>>(
      future: FlutterReadium().getResourceBytes(event.href).then((b) => b),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _loadingSpinner();
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _errorWidget(snapshot.error);
        }
        final bytes = snapshot.data!;
        return Image.memory(
          key: const ValueKey<String>('full_screen_image_memory'),
          Uint8List.fromList(bytes),
          errorBuilder: (context, error, stackTrace) => _errorWidget(error),
        );
      },
    );
  }

  Widget _loadingSpinner() => const Center(
    key: ValueKey<String>('full_screen_image_loading'),
    child: CircularProgressIndicator(color: Colors.white),
  );

  Widget _errorWidget(Object? error) => Center(
    key: const ValueKey<String>('full_screen_image_error'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image, color: Colors.white54, size: 64),
        const SizedBox(height: 8),
        Text(
          'Could not load image',
          style: const TextStyle(color: Colors.white54),
        ),
      ],
    ),
  );
}
