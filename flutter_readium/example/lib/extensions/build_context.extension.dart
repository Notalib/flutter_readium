import 'package:flutter/material.dart';

enum ScreenBreakpointEnum {
  xsm,
  sm,
  md,
  lg,
  xl,
}

extension ContextExtension on BuildContext {
  bool get isxSmallScreen => portraitBreakpoint.name == ScreenBreakpointEnum.xsm.name;
  bool get isSmallScreen => portraitBreakpoint.name == ScreenBreakpointEnum.sm.name;

  bool get isSmallDownScreen => isSmallScreen || isxSmallScreen; // is used

  Size get screenSize => MediaQuery.sizeOf(this);

  ScreenBreakpointEnum get portraitBreakpoint => _getScreenBreakpoint(screenSize.width);

  ScreenBreakpointEnum _getScreenBreakpoint(final num size) {
    if (size >= 1920) {
      return ScreenBreakpointEnum.xl;
    } else if (size >= 1440) {
      return ScreenBreakpointEnum.lg;
    } else if (size >= 1024) {
      return ScreenBreakpointEnum.md;
    } else if (size >= 600) {
      return ScreenBreakpointEnum.sm;
    }

    return ScreenBreakpointEnum.xsm;
  }
}
