import '../_index.dart';

extension PlaybackStateExtension on PlaybackState {
  String toDebugString() => 'PlaybackState('
      'processingState: ${processingState.toReadiumAudioStatus()?.name}, '
      'queueIndex: $queueIndex, '
      'playing: $playing, '
      'bufferedPosition: $bufferedPosition, '
      'updatePosition: $updatePosition, '
      'speed: $speed, '
      'errorCode: $errorCode, '
      'errorMessage: $errorMessage'
      ')';

  bool get hasError => errorCode != null || errorMessage != null;

  String get error => 'code: $errorCode -- message $errorMessage';
}

extension AudioProcessingStateExtension on AudioProcessingState {
  bool get isIdle => name == AudioProcessingState.idle.name;
  bool get isLoading => name == AudioProcessingState.loading.name;
  bool get isBuffering => name == AudioProcessingState.buffering.name;
  bool get isReady => name == AudioProcessingState.ready.name;
  bool get isCompleted => name == AudioProcessingState.completed.name;
  bool get isError => name == AudioProcessingState.error.name;

  ReadiumAudioStatus? toReadiumAudioStatus() {
    switch (this) {
      case AudioProcessingState.idle:
        return ReadiumAudioStatus.none;
      case AudioProcessingState.loading:
        return ReadiumAudioStatus.loading;
      case AudioProcessingState.buffering:
        return ReadiumAudioStatus.buffering;
      case AudioProcessingState.ready:
        return ReadiumAudioStatus.ready;
      case AudioProcessingState.completed:
        return ReadiumAudioStatus.endOfPublication;
      case AudioProcessingState.error:
        return ReadiumAudioStatus.error;
    }
  }
}
