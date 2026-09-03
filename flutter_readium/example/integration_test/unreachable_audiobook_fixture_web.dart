// Web stubs: the audio-recovery tests are native-only, so these compile but are
// never invoked.

final class StallingAudioServer {
  static Future<StallingAudioServer> start() {
    throw UnsupportedError('StallingAudioServer is native-only');
  }

  String get audioUrl => throw UnsupportedError('StallingAudioServer is native-only');

  Future<void> get firstRequest => throw UnsupportedError('StallingAudioServer is native-only');

  Future<void> close() async {}
}

Future<String> writeTempAudiobookManifest(String manifestJson) {
  throw UnsupportedError('writeTempAudiobookManifest is native-only');
}

Future<bool> isHostReachable(String url, {Duration timeout = const Duration(seconds: 5)}) {
  throw UnsupportedError('isHostReachable is native-only');
}
