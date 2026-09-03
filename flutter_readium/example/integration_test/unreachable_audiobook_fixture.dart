// Native helpers for deterministic audio-recovery integration tests. Web has
// no filesystem or dart:io server, so the conditional import swaps in stubs.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

Future<String> writeTempAudiobookManifest(String manifestJson) async {
  final dir = await Directory(
    p.join(Directory.systemTemp.path, 'frx_recovery_test'),
  ).create(recursive: true);
  final file = File(p.join(dir.path, 'manifest.json'));
  await file.writeAsString(manifestJson);
  return file.path;
}

/// Serves a few seconds of valid WAV audio, then leaves later reads pending.
/// The native player starts normally before entering a real buffering state.
final class StallingAudioServer {
  StallingAudioServer._(this._server) : _availableBytes = _makeWavePrefix();

  final HttpServer _server;
  final Uint8List _availableBytes;
  final Completer<void> _firstRequest = Completer<void>();
  final List<HttpResponse> _pendingResponses = [];

  static const _sampleRate = 8000;
  static const _bytesPerSample = 2;
  static const _declaredAudioSeconds = 60;
  static const _availableAudioSeconds = 4;
  static const _headerLength = 44;
  static const _totalLength = _headerLength + (_sampleRate * _bytesPerSample * _declaredAudioSeconds);

  static Future<StallingAudioServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = StallingAudioServer._(server);
    server.listen((request) => unawaited(fixture._handleRequest(request)));
    return fixture;
  }

  String get audioUrl => 'http://127.0.0.1:${_server.port}/track.mp3';

  Future<void> get firstRequest => _firstRequest.future;

  Future<void> _handleRequest(HttpRequest request) async {
    if (!_firstRequest.isCompleted) {
      _firstRequest.complete();
    }

    final response = request.response;
    response.headers.contentType = ContentType('audio', 'wav');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

    final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(
      request.headers.value(HttpHeaders.rangeHeader) ?? '',
    );
    if (match == null) {
      response.contentLength = _totalLength;
      response.add(_availableBytes);
      await response.flush();
      _pendingResponses.add(response);
      return;
    }

    final start = int.parse(match.group(1)!);
    if (start >= _availableBytes.length) {
      _pendingResponses.add(response);
      return;
    }

    final requestedEnd = int.tryParse(match.group(2) ?? '');
    final end = requestedEnd == null || requestedEnd >= _availableBytes.length
        ? _availableBytes.length - 1
        : requestedEnd;
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$_totalLength');
    response.contentLength = end - start + 1;
    response.add(_availableBytes.sublist(start, end + 1));
    await response.close();
  }

  Future<void> close() async {
    _pendingResponses.clear();
    await _server.close(force: true);
  }

  static Uint8List _makeWavePrefix() {
    final audioBytes = _sampleRate * _bytesPerSample * _availableAudioSeconds;
    final bytes = Uint8List(_headerLength + audioBytes);
    final header = ByteData.sublistView(bytes, 0, _headerLength);

    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        bytes[offset + index] = value.codeUnitAt(index);
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, _totalLength - 8, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, _sampleRate * _bytesPerSample, Endian.little);
    header.setUint16(32, _bytesPerSample, Endian.little);
    header.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, _totalLength - _headerLength, Endian.little);
    return bytes;
  }
}

/// True if [url]'s host answers at all within [timeout]. Any HTTP response
/// (including 401/403/404) counts as reachable; only a transport failure
/// (connection refused, DNS, TLS, timeout) counts as unreachable. Used to skip
/// the network-dependent auth test when the real host is down, without masking
/// a genuine misclassification when it is up.
Future<bool> isHostReachable(
  String url, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
    final response = await request.close().timeout(timeout);
    await response.drain<void>();
    return true;
  } on Object catch (e) {
    // Surface why the precheck failed so the skip reason distinguishes a DNS
    // failure (host not resolvable — e.g. an internal host from an Android
    // emulator) from a timeout or refused connection.
    debugPrint('isHostReachable($url) failed: $e');
    return false;
  } finally {
    client.close(force: true);
  }
}
