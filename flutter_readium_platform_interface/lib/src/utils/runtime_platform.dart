import 'package:flutter/foundation.dart';

class RuntimePlatform {
  static const web = 'web';
  static const mobile = 'mobile';

  static const isWeb = kIsWeb;
  static var isIOS = defaultTargetPlatform == TargetPlatform.iOS;
  static var isAndroid = defaultTargetPlatform == TargetPlatform.android;
  static var isMobile = isIOS || isAndroid;

  static const platform = isWeb ? web : mobile;
}
