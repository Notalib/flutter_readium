import 'package:flutter/foundation.dart';

class RuntimePlatform {
  static const web = 'web';
  static const mobile = 'mobile';

  static const isWeb = kIsWeb;
  static bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isMobile => isIOS || isAndroid;

  static const platform = isWeb ? web : mobile;
}
