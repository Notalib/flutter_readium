import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

/// Full-screen pinch-zoom image viewer shown when the user taps an image in
/// an EPUB.
///
/// The image is resolved lazily on all platforms via
/// [ReadiumResourceImageProvider] ([FlutterReadium.imageProvider]), which
/// resolves [ImageTapEvent.href] to a native-cached `file://` URL on
/// iOS/Android or the served resource URL on Web.
///
/// Dismiss by tapping the background or pressing the system back button.
class FullScreenImageView extends StatelessWidget {
  const FullScreenImageView({required this.event, super.key});

  final ImageTapEvent event;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  key: const ValueKey<String>('full_screen_image_gesture'),
                  boundaryMargin: const EdgeInsets.all(12.0),
                  clipBehavior: Clip.none,
                  minScale: 0.5,
                  maxScale: 10.0,
                  child: Center(child: _buildImage(context)),
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

  Widget _buildImage(BuildContext context) {
    // ReadiumResourceImageProvider handles caching and avoids re-fetching on rebuild.
    return Image(
      key: const ValueKey<String>('full_screen_image_memory'),
      image: FlutterReadium().imageProvider(event.href),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _loadingSpinner();
      },
      errorBuilder: (context, error, stackTrace) => _errorWidget(error),
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
