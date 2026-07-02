import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:flutter/painting.dart' show ImageDecoderCallback;

/// Loads an image codec for a non-`file://` resource URL via the browser's
/// native image decoder ([ui_web.createImageCodecFromUrl]) — the same
/// mechanism Flutter's own `NetworkImage`/`Image.network` use on Web.
///
/// This still requires the resource's server to send
/// `Access-Control-Allow-Origin`: CanvasKit needs pixel-level access to
/// decode any image (even for plain display), so its `<img>`-element decode
/// sets `crossOrigin = 'anonymous'` and its `fetch()` fallback hits the same
/// CORS check. There is no client-side way around this — see
/// `docs/troubleshooting.md` for the full explanation.
Future<ui.Codec> loadNetworkImageCodec(Uri uri, ImageDecoderCallback decode) => ui_web.createImageCodecFromUrl(uri);
