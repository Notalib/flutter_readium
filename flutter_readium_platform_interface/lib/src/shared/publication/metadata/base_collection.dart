import 'package:equatable/equatable.dart';

import '../../../../flutter_readium_platform_interface.dart';

/// Base class for collections of metadata, such as Series, StoryArc, Season, Issue, etc.
abstract class BaseCollection extends AdditionalProperties with EquatableMixin implements JSONable {
  const BaseCollection({
    required this.position,
    this.localizedName,
    this.identifier,
    this.altIdentifiers,
    this.localizedSortAs,
    this.links,
    super.additionalProperties,
  });

  final double? position;
  final LocalizedString? localizedName;
  final String? identifier;
  final List<AltIdentifier>? altIdentifiers;
  final LocalizedString? localizedSortAs;
  final List<Link>? links;

  String? get name => localizedName?.string;

  String? get sortAs => localizedSortAs?.string;
}

extension ListBaseCollectionExtension on List<BaseCollection>? {
  dynamic toSingleOrMultiJson() {
    if (this == null || this!.isEmpty) {
      return null;
    } else if (this!.length == 1) {
      return this!.first.toJson();
    } else {
      return this!.map((e) => e.toJson()).toList();
    }
  }
}
