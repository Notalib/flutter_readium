import '../../index.dart';

import 'package:json_annotation/json_annotation.dart';

enum PricePeriod {
  none,
  weekly,
  monthly,
  @JsonValue('bi-monthly')
  biMonthly,
  quarterly,
  @JsonValue('half-yearly')
  halfYearly,
  yearly,
}
