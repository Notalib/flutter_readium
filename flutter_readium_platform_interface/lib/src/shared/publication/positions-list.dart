import 'package:equatable/equatable.dart';

import '../../../flutter_readium_platform_interface.dart';

/// Readium's positions list: see https://github.com/readium/architecture/tree/master/models/locators/positions
class PositionsList with EquatableMixin implements JSONable {
  PositionsList({required this.total, required this.positions});

  final int total;
  final List<Locator> positions;

  @override
  List<Object?> get props => [total, positions];

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'total': total,
    'positions': positions.map((e) => e.toJson()).toList(),
  };

  static PositionsList? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);
    final total = jsonObject.optPositiveInt('total', remove: true);
    final positionsJson = jsonObject.optJsonArray('positions', remove: true);

    if (total == null || positionsJson == null) {
      return null;
    }

    final positions = positionsJson.map((locator) => Locator.fromJson(locator)).whereType<Locator>().toList();

    return PositionsList(total: total, positions: positions);
  }
}
