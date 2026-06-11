import '../index.dart';

/// Fired when the user taps an image inside an EPUB.
///
/// Emitted on iOS (via swift-toolkit's `ImageContentElement` target element)
/// and on Web (via DOM hit-testing). It never fires on Android — the
/// kotlin-toolkit has no equivalent image-tap API yet (tracked follow-up).
///
/// The event carries only the publication-relative [href] (plus lightweight
/// metadata); the image bytes are fetched lazily on demand via
/// `FlutterReadium.getResourceBytes` / `imageProvider`.
class ImageTapEvent implements JSONable {
  const ImageTapEvent({
    required this.href,
    this.caption,
    this.alt,
    this.rect,
    this.pixelWidth,
    this.pixelHeight,
    this.srcUrl,
  });

  factory ImageTapEvent.fromJson(final Map<String, dynamic> map) {
    final href = map.optString('href');
    if (href.isEmpty) {
      throw ArgumentError(
        'ImageTapEvent.fromJson: required field "href" is missing or empty',
      );
    }
    final rectMap = map['rect'] as Map<String, dynamic>?;
    return ImageTapEvent(
      href: href,
      caption: map.optNullableString('caption'),
      alt: map.optNullableString('alt'),
      rect: rectMap != null
          ? {
              'x': (rectMap['x'] as num?)?.toDouble() ?? 0.0,
              'y': (rectMap['y'] as num?)?.toDouble() ?? 0.0,
              'width': (rectMap['width'] as num?)?.toDouble() ?? 0.0,
              'height': (rectMap['height'] as num?)?.toDouble() ?? 0.0,
            }
          : null,
      pixelWidth: map.optNullableInt('pixelWidth'),
      pixelHeight: map.optNullableInt('pixelHeight'),
      srcUrl: map.optNullableString('srcUrl'),
    );
  }

  /// Publication-relative href of the tapped image resource.
  final String href;

  /// Optional caption associated with the image (platform-dependent).
  final String? caption;

  /// Optional alt text from the `<img>` element.
  final String? alt;

  /// On-screen bounding rectangle (`x`, `y`, `width`, `height`) in the content
  /// frame's coordinate space, if known.
  final Map<String, double>? rect;

  /// Natural pixel width of the image, if known.
  final int? pixelWidth;

  /// Natural pixel height of the image, if known.
  final int? pixelHeight;

  /// Absolute served URL of the image (Web only). When present it can be loaded
  /// directly via `Image.network`, skipping the byte bridge.
  final String? srcUrl;

  @override
  Map<String, dynamic> toJson() => {
    'href': href,
    if (caption != null) 'caption': caption,
    if (alt != null) 'alt': alt,
    if (rect != null) 'rect': rect,
    if (pixelWidth != null) 'pixelWidth': pixelWidth,
    if (pixelHeight != null) 'pixelHeight': pixelHeight,
    if (srcUrl != null) 'srcUrl': srcUrl,
  };
}
