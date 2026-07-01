import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show ImageDecoderCallback;
import 'package:http/http.dart' as http;

/// Loads an image codec for a non-`file://` resource URL by fetching its
/// bytes over HTTP.
///
/// Safe on native platforms — CORS is a browser-only restriction and does
/// not apply to a native HTTP client.
Future<ui.Codec> loadNetworkImageCodec(Uri uri, ImageDecoderCallback decode) async {
  final response = await http.get(uri);
  final buffer = await ui.ImmutableBuffer.fromUint8List(response.bodyBytes);
  return decode(buffer);
}
