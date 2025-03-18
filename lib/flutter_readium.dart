
import 'flutter_readium_platform_interface.dart';

class FlutterReadium {
  Future<String?> getPlatformVersion() {
    return FlutterReadiumPlatform.instance.getPlatformVersion();
  }
}
