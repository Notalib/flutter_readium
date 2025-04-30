// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_flutter_readium.dart';
import 'src/enums.dart';
import 'src/shared/index.dart';

export 'src/shared/index.dart';
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

  /// The default instance of [BatteryPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterReadium].
  static FlutterReadiumPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [BatteryPlatform] when they register themselves.
  static set instance(FlutterReadiumPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String> get platformVersion {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<Publication> openPublication(String pubUrl) {
    throw UnimplementedError('openPublication(pubUrl) has not been implemented.');
  }
}
