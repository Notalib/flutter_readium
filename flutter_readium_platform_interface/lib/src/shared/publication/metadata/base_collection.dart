import 'package:equatable/equatable.dart';

import '../../../../flutter_readium_platform_interface.dart';

abstract class BaseCollection extends AdditionalProperties with EquatableMixin implements JSONable {
  const BaseCollection({
    this.localizedName,
    this.identifier,
    this.altIdentifier,
    this.localizedSortAs,
    this.links,
    super.additionalProperties,
  });

  final LocalizedString? localizedName;
  final String? identifier;
  final AltIdentifier? altIdentifier;
  final LocalizedString? localizedSortAs;
  final List<Link>? links;
}
