import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Button that opens the system audio route picker (AirPlay and other outputs).
///
/// iOS only. Renders nothing on other platforms.
class ReadiumAudioRoutePicker extends StatelessWidget {
  const ReadiumAudioRoutePicker({
    super.key,
    this.size = 24,
    this.color,
    this.activeColor,
  });

  /// Width and height of the button.
  final double size;

  /// Icon colour when no external route is active. Defaults to the colour an [IconButton] would use here.
  final Color? color;

  /// Icon colour while an external route is active. Defaults to the theme's primary colour.
  final Color? activeColor;

  static const _viewType = 'dk.nota.flutter_readium/audio-route-picker';

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tint =
        color ??
        IconButtonTheme.of(context).style?.foregroundColor?.resolve(const {}) ??
        (theme.useMaterial3 ? theme.colorScheme.onSurfaceVariant : IconTheme.of(context).color);
    final activeTint = activeColor ?? theme.colorScheme.primary;
    return SizedBox.square(
      dimension: size,
      child: UiKitView(
        // Colours are creation params only, so a colour change must recreate the native view.
        key: ValueKey((tint, activeTint)),
        viewType: _viewType,
        creationParams: <String, Object?>{
          'tintColor': tint?.toARGB32(),
          'activeTintColor': activeTint.toARGB32(),
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
