import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<int> loadWebResourceBytes(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  if (!response.ok) {
    throw StateError('Failed to load web resource $url: HTTP ${response.status}');
  }

  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.lengthInBytes;
}
