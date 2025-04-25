import 'package:audio_session/audio_session.dart';

import '../_index.dart';

class ReadiumSwitchAudioHandler extends SwitchAudioHandler {
  ReadiumSwitchAudioHandler(this.handlers) : super(handlers.first) {
    // Configure the app's audio category and attributes for speech.
    AudioSession.instance.then((final session) {
      session.configure(const AudioSessionConfiguration.speech());
    });

    _observeReadiumPublication();
  }

  final List<AudioHandler> handlers;

  Future<void> _observeReadiumPublication() async {
    R2Log.d('Observing');
    final pubIdStream =
        FlutterReadium.stateStream.publication.map((final pub) => pub?.identifier).distinct();

    await for (final id in pubIdStream) {
      R2Log.d('publication changed $id');

      if (id != null) {
        await _setHandler();
      }
    }
    R2Log.d('Done');
  }

  Future<void> _setHandler() async {
    final state = FlutterReadium.state;
    // Switch to the right audio handler for this publication.
    final pub = state.publication;
    final opdsPublication = state.opdsPublication;

    if (pub == null || opdsPublication == null) {
      R2Log.d('Publication is null');

      return;
    }

    R2Log.d('Setting handler for ${opdsPublication.identifier}');

    final ReadiumAudioHandler handler;

    if (state.isAudiobook) {
      handler = await _switchHandler<Mp3AudioHandler>();
    } else if (state.hasText) {
      handler = await _switchHandler<TtsAudioHandler>();
    } else {
      R2Log.e(
        'Publication is neither audio nor text',
        data: opdsPublication,
      );

      return;
    }

    if (pub != FlutterReadium.state.publication) {
      R2Log.d('Publication changed while switching handler.');

      return;
    }

    return handler.setPublication();
  }

  Future<ReadiumAudioHandler> _switchHandler<T>() async {
    R2Log.d('Set handler to $T');

    final handler = handlers.firstWhere((final handler) => handler is T);

    if (inner == handler) {
      R2Log.d('Already set as ${inner.runtimeType}');

      return inner as ReadiumAudioHandler;
    }

    R2Log.d('Changing handler ${inner.runtimeType} -> $T');
    inner = handler;

    return inner as ReadiumAudioHandler;
  }
}
