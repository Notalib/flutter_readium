// Native (VM) implementation: writes a caller-supplied manifest JSON string to
// a temp file and returns its path, for the audio-recovery integration test.
// Web has no filesystem for this (and the test is native-only), so the
// conditional import below swaps in a throwing stub there.

import 'dart:io';

import 'package:path/path.dart' as p;

Future<String> writeTempAudiobookManifest(String manifestJson) async {
  final dir = await Directory(
    p.join(Directory.systemTemp.path, 'frx_recovery_test'),
  ).create(recursive: true);
  final file = File(p.join(dir.path, 'manifest.json'));
  await file.writeAsString(manifestJson);
  return file.path;
}
