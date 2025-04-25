import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';

import '../_index.dart';
import 'readium_audio_handler_custom_actions.dart';

abstract class ReadiumAudioHandler extends BaseAudioHandler {
  final externalAudioOutputTypes = <AudioDeviceType>{
    AudioDeviceType.bluetoothA2dp,
    AudioDeviceType.bluetoothLe,
    AudioDeviceType.bluetoothSco,
    AudioDeviceType.wiredHeadset,
    AudioDeviceType.wiredHeadphones,
    AudioDeviceType.carAudio,
    AudioDeviceType.airPlay,
  };

  FutureOr<XmlDocument?> getDocument(final String href);

  Future<void> publicationUpdated();

  Future<void> setPublication() async {
    final state = FlutterReadium.state;
    final publication = state.publication;
    final locator = state.currentLocator;

    if (publication == null) {
      R2Log.d('No publication is set!');

      return;
    }

    R2Log.d(() => 'pub: ${publication.identifier}, initialLocator: $locator');

    if (state.isAudiobook) {
      FlutterReadium.updateState(
        audioStatus: ReadiumAudioStatus.loading,
      );
    }

    await publicationUpdated();

    R2Log.d('Updated');

    _observePlaybackState();
    _observeSkipIntervalDuration();
  }

  @mustCallSuper
  @override
  Future<void> play() async {
    R2Log.d('Play');

    final publication = FlutterReadium.state.publication;
    if (publication == null) {
      const errorMessage = 'Publication NOT set!, try to open a publication first';
      FlutterReadium.updateState(
        playing: false,
        autoPlay: false,
        error: ReadiumError(errorMessage),
      );
      throw const PublicationNotSetReadiumException(errorMessage);
    }

    return super.play();
  }

  @mustCallSuper
  @override
  Future<void> pause() async {
    R2Log.d('Pause playback');

    // Fix to ensure that play/pause button works on iOS when external audio output is connected.
    if (Platform.isIOS && !FlutterReadium.state.playing) {
      final isExternalOutput = await _isExternalAudioOutputConnected();
      // Playing state is checked twice, because state would sometimes change while awaiting _isExternalAudioOutputConnected.
      // Which results in tts repeating the first paragraph. 
      if (isExternalOutput && !FlutterReadium.state.playing) {
        FlutterReadium.updateState(
          playing: true,
          autoPlay: false,
        );
        FlutterReadium.audioHandler.click();
        return play();
      }
    }

    FlutterReadium.updateState(
      playing: false,
      autoPlay: false,
    );

    return super.pause();
  }

  @mustCallSuper
  @override
  Future<void> stop() async {
    R2Log.d('Stop');

    // Reset the Error and processingState on stop.
    playbackState.value = playbackState.value.copyWith(
      processingState: AudioProcessingState.ready,
      errorCode: null,
      errorMessage: null,
    );

    return super.stop();
  }

  @override
  Future<dynamic> customAction(final String name, [final Map<String, dynamic>? extras]) async {
    R2Log.d(name);
    try {
      switch (name) {
        case ReadiumAudioHandlerCustomActions.skipToNextParagraph:
          return skipToNextParagraph();
        case ReadiumAudioHandlerCustomActions.skipToPreviousParagraph:
          return skipToPreviousParagraph();
        case ReadiumAudioHandlerCustomActions.go:
          return go(
            extras![ReadiumAudioHandlerCustomActions.goPayloadKey] as Locator,
          );
        case ReadiumAudioHandlerCustomActions.pauseFade:
          return pauseFade();
        case ReadiumAudioHandlerCustomActions.cleanup:
          return cleanup();
        case ReadiumAudioHandlerCustomActions.getTtsVoices:
          return getTtsVoices(
            fallbackLang:
                extras![ReadiumAudioHandlerCustomActions.getTtsVoicesPayloadKey] as List<String>?,
          );
        case ReadiumAudioHandlerCustomActions.setTtsVoice:
          return setTtsVoice(
            extras![ReadiumAudioHandlerCustomActions.setTtsVoicePayloadKey] as ReadiumTtsVoice,
          );
        default:
          return super.customAction(name, extras);
      }
    } on Object catch (e) {
      R2Log.e(
        e,
        data: {
          'name': name,
          'extras': extras,
        },
      );

      rethrow;
    }
  }

  void _observeSkipIntervalDuration() async {
    R2Log.d('Observing');

    await for (final duration in FlutterReadium.stateStream.skipIntervalDuration) {
      R2Log.d('Changed $duration');

      AudioService.updateConfig(
        AudioServiceConfig(
          rewindInterval: duration,
          fastForwardInterval: duration,
        ),
      );
    }

    R2Log.d('Done');
  }

  /// Converts audio_service state to flutter_readium state.
  void _observePlaybackState() async {
    R2Log.d('Observing');

    await for (final pState in playbackState.takeUntilPublicationChanged.distinct()) {
      R2Log.d(() => 'Changed ${pState.toDebugString()}');

      final state = FlutterReadium.state;

      final status = pState.processingState.toReadiumAudioStatus() ?? state.audioStatus;

      final errorCode = pState.errorCode;
      final errorMessage = pState.errorMessage;

      final hasError = errorCode != null || errorMessage != null || pState.processingState.isError;

      // Set autoPlay to false when playback is started.
      final autoPlay = state.autoPlay && !hasError && !pState.playing;
      final playing =
          (pState.playing && !pState.processingState.isCompleted && !hasError) || autoPlay;

      FlutterReadium.updateState(
        audioStatus: status,
        playing: playing,
        autoPlay: autoPlay,
      );
    }

    R2Log.d('Done');
  }

  /// Sets audio progress. If this results in highlighting on a new page in the reader_widget, waits
  /// for the widget to finish changing page.
  @mustCallSuper
  Future<void> setProgress(final Locator locator) async {
    final href = locator.href;
    R2Log.d(() => 'link.href: $href, progress: $locator');

    final state = FlutterReadium.state;

    FlutterReadium.updateState(
      audioStatus: state.audioLocator?.hrefPath != locator.hrefPath
          ? ReadiumAudioStatus.loading
          : state.audioStatus,
      audioLocator: state.publication == null ? null : locator,
    );
  }

  Future<void> skipToNextParagraph() async => R2Log.e('Unimplemented');

  Future<void> skipToPreviousParagraph() async => R2Log.e('Unimplemented');

  Future<void> go(final Locator locator);

  Future<void> setSkipInterval(final Duration duration) async => R2Log.e('Unimplemented');

  Future<void> pauseFade() async => R2Log.e('Unimplemented');

  Future<List<ReadiumTtsVoice>> getTtsVoices({final List<String>? fallbackLang}) =>
      throw Exception('Unimplemented');

  Future<void> setTtsVoice(final ReadiumTtsVoice selectedVoice) => throw Exception('Unimplemented');

  /// Should be called on publication close.
  @mustCallSuper
  Future<void> cleanup() async {
    playbackState.value = PlaybackState();
  }

  bool _includesExternalAudioOutput(final Set<AudioDevice> devices) => devices
      .map((final device) => device.type)
      .toSet()
      .intersection(externalAudioOutputTypes)
      .isNotEmpty;

  Future<bool> _isExternalAudioOutputConnected() async {
    final session = await AudioSession.instance;
    final devices = await session.getDevices(includeInputs: false);
    final isExternalOutputConnected = _includesExternalAudioOutput(devices);
    R2Log.i('AudioHandler: External audio output connected? $isExternalOutputConnected');
    return isExternalOutputConnected;
  }

  @override
  String toString() =>
      'publication:${FlutterReadium.state.publication?.identifier},playbackState:${playbackState.value})';
}
