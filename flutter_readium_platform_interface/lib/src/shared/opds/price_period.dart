import '../index.dart';

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
