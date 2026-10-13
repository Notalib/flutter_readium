import 'package:flutter/foundation.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native platform flags exclude web and follow the default target platform', () {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    addTearDown(() => debugDefaultTargetPlatformOverride = originalPlatform);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(RuntimePlatform.isIOS, !kIsWeb);
    expect(RuntimePlatform.isAndroid, isFalse);
    expect(RuntimePlatform.isMobile, !kIsWeb);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(RuntimePlatform.isIOS, isFalse);
    expect(RuntimePlatform.isAndroid, !kIsWeb);
    expect(RuntimePlatform.isMobile, !kIsWeb);
  });
}
