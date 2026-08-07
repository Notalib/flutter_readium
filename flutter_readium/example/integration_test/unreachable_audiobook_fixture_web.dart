// Web stub: the audio-recovery test that uses this is native-only (see the
// kIsWeb skip at its call site), so this must compile but is never invoked.

Future<String> writeTempAudiobookManifest(String manifestJson) {
  throw UnsupportedError('writeTempAudiobookManifest is native-only');
}

Future<bool> isHostReachable(String url, {Duration timeout = const Duration(seconds: 5)}) {
  throw UnsupportedError('isHostReachable is native-only');
}
