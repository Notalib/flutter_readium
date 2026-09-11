import 'package:meta/meta.dart';

import '../utils/jsonable.dart';

/// Identifies a Flutter asset (JS or CSS file) to inject into EPUB HTML resources.
///
/// [assetPath] is the asset path as declared in `pubspec.yaml`, e.g. `assets/custom.js`.
/// [package] is the pub package that owns the asset, or `null` for app-level assets.
/// The file type is inferred from the path extension (`.js` or `.css`).
@immutable
class InjectionAsset implements JSONable {
  const InjectionAsset({required this.assetPath, this.package});

  factory InjectionAsset.fromJson(Map<String, dynamic> json) => InjectionAsset(
    assetPath: json['assetPath'] as String,
    package: json['package'] as String?,
  );

  final String assetPath;
  final String? package;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('assetPath', assetPath)
    ..putOpt('package', package);
}
