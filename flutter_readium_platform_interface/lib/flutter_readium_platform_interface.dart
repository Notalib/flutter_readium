// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_flutter_readium.dart';
import 'src/enums.dart';
import 'src/reader/index.dart';
import 'src/shared/index.dart';

export 'src/exceptions/index.dart';
export 'src/extensions/index.dart';
export 'src/reader/index.dart';
export 'src/shared/index.dart';
export 'src/utils/index.dart';
export 'src/enums.dart';

/// The interface that implementations of FlutterReadium must implement.
///
/// Platform implementations should extend this class rather than implement it as `FlutterReadium`
/// does not consider newly added methods to be breaking changes. Extending this class
/// (using `extends`) ensures that the subclass will get the default implementation, while
/// platform implementations that `implements` this interface will be broken by newly added
/// [FlutterReadiumPlatform] methods.
abstract class FlutterReadiumPlatform extends PlatformInterface {
  /// Constructs a BatteryPlatform.
  FlutterReadiumPlatform() : super(token: _token);

  static final Object _token = Object();
  static FlutterReadiumPlatform _instance = MethodChannelFlutterReadium();
  static FlutterReadiumPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [FlutterReadiumPlatform] when they register themselves.
  static set instance(final FlutterReadiumPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  ReadiumReaderWidgetInterface? currentReaderWidget;
  EPUBPreferences? defaultPreferences;

  void setDefaultPreferences(EPUBPreferences preferences) {
    defaultPreferences = preferences;
  }

  /// Load publication manifest from URL, which is usually a packaged ebook or direct URL to a manifest.
  Future<Publication> loadPublication(String pubUrl) =>
      throw UnimplementedError('loadPublication(pubUrl) has not been implemented.');

  /// Opens a publication from a URL and prepares it for reading or playback.
  /// If the URL has not already been loaded, it will implicitly do this.
  Future<Publication> openPublication(String pubUrl) =>
      throw UnimplementedError('openPublication(pubUrl) has not been implemented.');

  /// Close the currently open publication and its related reader or playback ressources.
  Future<void> closePublication() => throw UnimplementedError('closePublication() has not been implemented.');

  Future<String?> getLinkContent(final Link link);

  Future<void> goLeft() => throw UnimplementedError('goLeft() has not been implemented.');
  Future<void> goRight() => throw UnimplementedError('goRight() has not been implemented.');

  //TODO: Consider if we need this and naming. Currently skips to next/previous chapter.
  Future<void> skipToNext() => throw UnimplementedError('skipToNext() has not been implemented.');
  Future<void> skipToPrevious() => throw UnimplementedError('skipToPrevious() has not been implemented.');

  /// Sets the default EPUB rendering preferences and updates preferences for any current ReaderWidgetViews.
  Future<void> setEPUBPreferences(EPUBPreferences preferences) =>
      throw UnimplementedError('applyDecorations() has not been implemented');

  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) =>
      throw UnimplementedError('applyDecorations() has not been implemented');

  // TTS API - BEGIN
  Future<void> ttsEnable(TTSPreferences? preferences) =>
      throw UnimplementedError('ttsEnable() has not been implemented');
  Future<void> ttsStart(Locator? fromLocator) => throw UnimplementedError('ttsStart() has not been implemented');
  Future<void> stop() => throw UnimplementedError('ttsStop() has not been implemented');
  Future<void> pause() => throw UnimplementedError('ttsPause() has not been implemented');
  Future<void> resume() => throw UnimplementedError('ttsResume() has not been implemented');
  Future<void> next() => throw UnimplementedError('ttsNext() has not been implemented');
  Future<void> previous() => throw UnimplementedError('ttsPrevious() has not been implemented');
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() =>
      throw UnimplementedError('ttsGetAvailableVoices() has not been implemented');
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) =>
      throw UnimplementedError('ttsSetVoice() has not been implemented');
  Future<void> ttsSetDecorationStyle(
    ReaderDecorationStyle? utteranceDecoration,
    ReaderDecorationStyle? rangeDecoration,
  ) =>
      throw UnimplementedError('ttsSetDecorationStyle() has not been implemented');
  Future<void> ttsSetPreferences(TTSPreferences preferences) =>
      throw UnimplementedError('ttsSetPreferences() has not been implemented');
  // TTS API - END

  // AudioBook API - BEGIN
  Future<void> audioStart({double speed = 1.0, Locator? fromLocator}) =>
      throw UnimplementedError('audioStart() has not been implemented');
  // AudioBook API - END

  Stream<ReadiumReaderStatus> get onReaderStatusChanged {
    throw UnimplementedError('onReaderStatus stream has not been implemented.');
  }

  Stream<Locator> get onTextLocatorChanged {
    throw UnimplementedError('onTextLocatorChanged stream has not been implemented.');
  }

  Stream<Locator> get onAudioLocatorChanged {
    throw UnimplementedError('onAudioLocatorChanged stream has not been implemented.');
  }
}
