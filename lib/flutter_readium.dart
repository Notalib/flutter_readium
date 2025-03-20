import 'flutter_readium_platform_interface.dart';

class FlutterReadium {
  Future<String?> getPlatformVersion() {
    return FlutterReadiumPlatform.instance.getPlatformVersion();
  }

  Future<String?> openPublication(String pubUrl) {
    return FlutterReadiumPlatform.instance.openPublication(pubUrl);
  }
}
