import 'package:flutter/material.dart';

extension ReadiumTargetPlatformExtension on TargetPlatform {
  bool get isAndroid => name == TargetPlatform.android.name;
  bool get isFuchsia => name == TargetPlatform.fuchsia.name;
  bool get isIOS => name == TargetPlatform.iOS.name;
  bool get isLinux => name == TargetPlatform.linux.name;
  bool get isMacOS => name == TargetPlatform.macOS.name;
  bool get isWindows => name == TargetPlatform.windows.name;
}
