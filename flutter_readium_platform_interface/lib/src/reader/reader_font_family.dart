import 'package:meta/meta.dart';

/// The style of a static reader font face.
enum ReaderFontStyle { normal, italic }

/// A static font face supplied as a Flutter asset.
@immutable
class ReaderFontFace {
  const ReaderFontFace({
    required this.asset,
    this.style = ReaderFontStyle.normal,
    this.weight = 400,
  }) : assert(asset != '', 'asset must not be empty'),
       assert(weight >= 1 && weight <= 1000, 'weight must be between 1 and 1000');

  /// The Flutter asset path, for example `assets/fonts/Atkinson-Regular.ttf`.
  final String asset;

  /// The face style.
  final ReaderFontStyle style;

  /// The CSS numeric font weight.
  final int weight;

  Map<String, Object> toMap() => {
    'asset': asset,
    'style': style.name,
    'weight': weight,
  };

  static ReaderFontFace fromMap(final Map<String, dynamic> map) {
    final asset = map['asset'];
    final style = map['style'];
    final weight = map['weight'];
    if (asset is! String || asset.isEmpty) {
      throw ArgumentError.value(asset, 'asset', 'must not be empty');
    }
    if (style is! String || !ReaderFontStyle.values.any((value) => value.name == style)) {
      throw ArgumentError.value(style, 'style', 'must be normal or italic');
    }
    if (weight is! int || weight < 1 || weight > 1000) {
      throw ArgumentError.value(weight, 'weight', 'must be between 1 and 1000');
    }
    return ReaderFontFace(
      asset: asset,
      style: ReaderFontStyle.values.byName(style),
      weight: weight,
    );
  }
}

/// A family of static font faces supplied as Flutter assets.
@immutable
class ReaderFontFamily {
  // A runtime assertion on [faces] prevents this constructor from being const.
  // ignore: prefer_const_constructors_in_immutables
  ReaderFontFamily({
    required this.name,
    required this.faces,
    this.fallbacks = const [],
  }) : assert(name != '', 'name must not be empty'),
       assert(faces.isNotEmpty, 'faces must not be empty');

  /// The family name used by EPUB preferences.
  final String name;

  /// Optional fallback family names used when a glyph is unavailable.
  final List<String> fallbacks;

  /// Static faces belonging to this family.
  final List<ReaderFontFace> faces;

  Map<String, Object> toMap() => {
    'name': name,
    'fallbacks': fallbacks,
    'faces': faces.map((face) => face.toMap()).toList(),
  };

  static ReaderFontFamily fromMap(final Map<String, dynamic> map) {
    final name = map['name'];
    final fallbacks = map['fallbacks'];
    final faces = map['faces'];
    if (name is! String || name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (fallbacks != null || map.containsKey('fallbacks')) {
      if (fallbacks is! List || fallbacks.any((value) => value is! String || value.isEmpty)) {
        throw ArgumentError.value(fallbacks, 'fallbacks', 'must contain non-empty strings');
      }
    }
    if (faces is! List || faces.isEmpty || faces.any((face) => face is! Map)) {
      throw ArgumentError.value(faces, 'faces', 'must contain at least one face map');
    }
    return ReaderFontFamily(
      name: name,
      fallbacks: fallbacks == null ? const [] : List<String>.from(fallbacks),
      faces: faces.map((face) => ReaderFontFace.fromMap(Map<String, dynamic>.from(face as Map))).toList(),
    );
  }
}
