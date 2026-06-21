import 'dart:ui' show Rect;

import '../index.dart';

/// Fired when the user taps an image inside an EPUB.
///
/// Emitted on iOS (via swift-toolkit's `ImageContentElement` target element),
/// on Android (via a `@JavascriptInterface` bridge injected into each resource
/// WebView), and on Web (via DOM hit-testing).
///
/// The event carries only the publication-relative [href] (plus lightweight
/// metadata); the image bytes are fetched lazily on demand via
/// `FlutterReadium.getResourceBytes` / `imageProvider`.
///
/// The event fires for *every* tapped image, including images inside a Nota
/// comic book. The plugin does not filter by publication type — deciding
/// whether to act on a tap (e.g. open a full-screen viewer, or ignore it for
/// comic books) is the consumer's responsibility.
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
          ? Rect.fromLTWH(
              (rectMap['x'] as num?)?.toDouble() ?? 0.0,
              (rectMap['y'] as num?)?.toDouble() ?? 0.0,
              (rectMap['width'] as num?)?.toDouble() ?? 0.0,
              (rectMap['height'] as num?)?.toDouble() ?? 0.0,
            )
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

  /// On-screen bounding rectangle in the content frame's coordinate space,
  /// if known. [Rect.left]/[Rect.top] are the x/y origin; use
  /// [Rect.width]/[Rect.height] for dimensions.
  final Rect? rect;

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
    if (rect != null)
      'rect': {
        'x': rect!.left,
        'y': rect!.top,
        'width': rect!.width,
        'height': rect!.height,
      },
    if (pixelWidth != null) 'pixelWidth': pixelWidth,
    if (pixelHeight != null) 'pixelHeight': pixelHeight,
    if (srcUrl != null) 'srcUrl': srcUrl,
  };
}
