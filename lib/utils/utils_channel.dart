import 'package:flutter/services.dart' show MethodChannel;

const _channelName = 'dk.nota.flutter_readium/Utils';
const _channel = MethodChannel(_channelName);

class UtilsChannel {
  static UtilsChannel? _instance;

  static UtilsChannel get instance {
    _instance ??= UtilsChannel();
    return _instance!;
  }

  Future<double?> getFreeDiskSpaceInMB() async {
    final result = await _channel.invokeMethod<double?>('getFreeDiskSpaceInMB');
    return result;
  }
}
