import 'dart:io';

import '../integration_test/web_fixture_origin.dart';

/// Serves generated fixtures with ranges, which Flutter's dev server ignores.
Future<HttpServer> startWebFixtureServer(Directory directory, {int? port}) async {
  final root = Directory(await directory.resolveSymbolicLinks());
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port ?? Uri.parse(webFixtureOrigin).port);
  server.listen((request) async {
    final response = request.response;
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Range')
      ..set('Access-Control-Expose-Headers', 'Accept-Ranges, Content-Range, Content-Length')
      ..set('Accept-Ranges', 'bytes');
    try {
      await _serveFixture(request, root);
    } on FileSystemException {
      response.statusCode = HttpStatus.notFound;
    } finally {
      await response.close();
    }
  });
  return server;
}

Future<void> _serveFixture(HttpRequest request, Directory root) async {
  final response = request.response;
  if (request.method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    return;
  }
  if (request.method != 'GET' && request.method != 'HEAD') {
    response.statusCode = HttpStatus.methodNotAllowed;
    response.headers.set('Allow', 'GET, HEAD, OPTIONS');
    return;
  }
  final segments = request.uri.pathSegments;
  if (segments.isEmpty || segments.first != 'test-fixtures') {
    response.statusCode = HttpStatus.notFound;
    return;
  }
  final path = segments.skip(1).toList();
  if (path.isEmpty ||
      path.any(
        (segment) =>
            segment.isEmpty || segment == '.' || segment == '..' || segment.contains('/') || segment.contains(r'\'),
      )) {
    response.statusCode = HttpStatus.forbidden;
    return;
  }
  final file = File.fromUri(root.uri.resolveUri(Uri(pathSegments: path)));
  final canonicalPath = await file.resolveSymbolicLinks();
  if (!canonicalPath.startsWith('${root.path}${Platform.pathSeparator}')) {
    response.statusCode = HttpStatus.forbidden;
    return;
  }
  final length = await file.length();
  var start = 0;
  var end = length - 1;
  final range = request.headers.value(HttpHeaders.rangeHeader);
  if (range != null) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
    final first = match == null ? null : int.tryParse(match[1]!);
    final last = match == null ? null : int.tryParse(match[2]!);
    final malformed =
        match == null || (match[1]!.isNotEmpty && first == null) || (match[2]!.isNotEmpty && last == null);
    if (malformed ||
        length == 0 ||
        (first == null && last == null) ||
        (first == null && last! <= 0) ||
        (first != null && (first >= length || (last != null && last < first)))) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      response.contentLength = 0;
      return;
    }
    if (first == null) {
      start = length - last!;
      if (start < 0) start = 0;
    } else {
      start = first;
      if (last != null && last < end) end = last;
    }
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
  }
  final extension = path.last.split('.').last.toLowerCase();
  response.headers.contentType = ContentType.parse(_mimeTypes[extension] ?? 'application/octet-stream');
  response.contentLength = end - start + 1;
  if (request.method == 'GET') await response.addStream(file.openRead(start, end + 1));
}

const _mimeTypes = {
  'json': 'application/json',
  'xhtml': 'application/xhtml+xml',
  'html': 'text/html',
  'css': 'text/css',
  'js': 'text/javascript',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'svg': 'image/svg+xml',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
};
