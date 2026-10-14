import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../test_driver/web_fixture_server.dart';

void main() {
  late Directory directory;
  late Directory root;
  late HttpServer server;
  late HttpClient client;
  late Uri origin;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('web-fixture-server-');
    root = await Directory('${directory.path}/fixtures').create();
    await File('${root.path}/track.mp3').writeAsString('0123456789');
    await File('${root.path}/manifest.json').writeAsString('{}');
    await File('${directory.path}/secret.txt').writeAsString('outside root');
    server = await startWebFixtureServer(root, port: 0);
    origin = Uri.parse('http://127.0.0.1:${server.port}');
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<(HttpClientResponse, String)> request(String path, {String method = 'GET', String? range}) async {
    final request = await client.openUrl(method, origin.resolve(path));
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (response, body);
  }

  test('full response supplies MIME, length, CORS and range capability', () async {
    final (response, body) = await request('/test-fixtures/track.mp3');
    expect(response.statusCode, HttpStatus.ok);
    expect(body, '0123456789');
    expect(response.contentLength, 10);
    expect(response.headers.contentType?.mimeType, 'audio/mpeg');
    expect(response.headers.value('Accept-Ranges'), 'bytes');
    expect(response.headers.value('Access-Control-Allow-Origin'), '*');
    final (manifest, _) = await request('/test-fixtures/manifest.json');
    expect(manifest.headers.contentType?.mimeType, 'application/json');
  });

  test('bounded, open-ended and suffix ranges return exact bytes', () async {
    for (final (range, bytes, contentRange) in [
      ('bytes=2-5', '2345', 'bytes 2-5/10'),
      ('bytes=7-', '789', 'bytes 7-9/10'),
      ('bytes=-3', '789', 'bytes 7-9/10'),
      ('bytes=7-99', '789', 'bytes 7-9/10'),
    ]) {
      final (response, body) = await request('/test-fixtures/track.mp3', range: range);
      expect(response.statusCode, HttpStatus.partialContent);
      expect(body, bytes);
      expect(response.contentLength, bytes.length);
      expect(response.headers.value(HttpHeaders.contentRangeHeader), contentRange);
    }
  });

  test('invalid and multiple ranges return 416 with resource length', () async {
    for (final range in [
      'bytes=10-',
      'bytes=5-2',
      'bytes=-0',
      'bytes=-',
      'bytes=0-1,4-5',
      'bytes=999999999999999999999999-1',
      'invalid',
    ]) {
      final (response, body) = await request('/test-fixtures/track.mp3', range: range);
      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(response.headers.value(HttpHeaders.contentRangeHeader), 'bytes */10');
      expect(body, isEmpty);
    }
  });

  test('HEAD preserves full and partial headers without a body', () async {
    for (final range in [null, 'bytes=2-5']) {
      final (response, body) = await request('/test-fixtures/track.mp3', method: 'HEAD', range: range);
      expect(response.statusCode, range == null ? HttpStatus.ok : HttpStatus.partialContent);
      expect(response.contentLength, range == null ? 10 : 4);
      expect(body, isEmpty);
    }
  });

  test('paths outside fixture root and escaping symlinks are rejected', () async {
    final (traversal, _) = await request('/test-fixtures/%2e%2e/secret.txt');
    // Uri.resolve normalizes encoded dot segments before sending the request.
    expect(traversal.statusCode, HttpStatus.notFound);
    final (encodedSeparator, _) = await request('/test-fixtures/..%2fsecret.txt');
    expect(encodedSeparator.statusCode, HttpStatus.forbidden);
    await Link('${root.path}/escape.txt').create('${directory.path}/secret.txt');
    final (symlink, _) = await request('/test-fixtures/escape.txt');
    expect(symlink.statusCode, HttpStatus.forbidden);
    final (missing, _) = await request('/test-fixtures/missing.mp3');
    expect(missing.statusCode, HttpStatus.notFound);
  });

  test('preflight allows range requests and other methods cannot write fixtures', () async {
    final (preflight, _) = await request('/test-fixtures/track.mp3', method: 'OPTIONS');
    expect(preflight.statusCode, HttpStatus.noContent);
    expect(preflight.headers.value('Access-Control-Allow-Headers'), 'Range');
    final (post, _) = await request('/test-fixtures/track.mp3', method: 'POST');
    expect(post.statusCode, HttpStatus.methodNotAllowed);
    expect(await File('${root.path}/track.mp3').readAsString(), '0123456789');
  });
}
