import 'package:equatable/equatable.dart';

import '../../../../flutter_readium_platform_interface.dart';

/// Base class for collections of metadata, such as Series, StoryArc, Season, Issue, etc.
abstract class BaseCollection extends AdditionalProperties with EquatableMixin implements JSONable {
  const BaseCollection({
    this.localizedName,
    this.identifier,
    this.altIdentifiers,
    this.localizedSortAs,
    this.links,
    super.additionalProperties,
  });

  final LocalizedString? localizedName;
  final String? identifier;
  final List<AltIdentifier>? altIdentifiers;
  final LocalizedString? localizedSortAs;
  final List<Link>? links;

  String? get name => localizedName?.string;
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
