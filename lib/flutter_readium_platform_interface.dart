import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_readium_method_channel.dart';

abstract class FlutterReadiumPlatform extends PlatformInterface {
  /// Constructs a FlutterReadiumPlatform.
  FlutterReadiumPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterReadiumPlatform _instance = MethodChannelFlutterReadium();

  /// The default instance of [FlutterReadiumPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterReadium].
  static FlutterReadiumPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterReadiumPlatform] when
  /// they register themselves.
  static set instance(FlutterReadiumPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
