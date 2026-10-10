import 'package:flutter/foundation.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native platform flags follow the default target platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(RuntimePlatform.isIOS, isTrue);
    expect(RuntimePlatform.isAndroid, isFalse);
    expect(RuntimePlatform.isMobile, isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(RuntimePlatform.isIOS, isFalse);
    expect(RuntimePlatform.isAndroid, isTrue);
    expect(RuntimePlatform.isMobile, isTrue);

    debugDefaultTargetPlatformOverride = null;
  });
}
