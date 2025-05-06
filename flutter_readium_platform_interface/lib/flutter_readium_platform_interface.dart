// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_flutter_readium.dart';
import 'src/enums.dart';
import 'src/reader/index.dart' show ReadiumReaderWidgetInterface, ReaderDecoration, EPUBPreferences;
import 'src/shared/index.dart';

export 'src/shared/index.dart';
export 'src/utils/index.dart';
export 'src/enums.dart';
export 'src/reader/index.dart' show ReadiumReaderWidget, ReaderDecoration, EPUBPreferences;

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
  static set instance(FlutterReadiumPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  ReadiumReaderWidgetInterface? currentReaderWidget;
  EPUBPreferences? defaultPreferences;

  Future<Publication> openPublication(String pubUrl) {
    throw UnimplementedError('openPublication(pubUrl) has not been implemented.');
  }

  Future<void> goLeft() => throw UnimplementedError('goLeft() has not been implemented.');
  Future<void> goRight() => throw UnimplementedError('goRight() has not been implemented.');
  Future<void> skipToNext() => throw UnimplementedError('skipToNext() has not been implemented.');
  Future<void> skipToPrevious() =>
      throw UnimplementedError('skipToPrevious() has not been implemented.');

  /// Sets the default EPUB rendering preferences and updates preferences for any current ReaderWidgetViews.
  Future<void> setEPUBPreferences(EPUBPreferences preferences) =>
      throw UnimplementedError('applyDecorations() has not been implemented');

  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) =>
      throw UnimplementedError('applyDecorations() has not been implemented');

  Stream<ReadiumReaderStatus> get onReaderStatusChanged {
    throw UnimplementedError('onReaderStatus stream has not been implemented.');
  }

  Stream<Locator> get onTextLocatorChanged {
    throw UnimplementedError('onTextLocatorChanged stream has not been implemented.');
  }
}
