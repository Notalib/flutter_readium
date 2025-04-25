import '../index.dart';

enum SubscriptionFrequency {
  @JsonValue('DAILY')
  daily,
  @JsonValue('WEEKLY')
  weekly,
  @JsonValue('WEEKLY1')
  weekly1,
  @JsonValue('WEEKLY2')
  weekly2,
  @JsonValue('WEEKLY3')
  weekly3,
  @JsonValue('WEEKLY4')
  weekly4,
  @JsonValue('WEEKLY5')
  weekly5,
  @JsonValue('WEEKLY6')
  weekly6,
  @JsonValue('WEEKLY7')
  weekly7,
  @JsonValue('MONTHLY')
  monthly,
  @JsonValue('QUARTERLY')
  quarterly,
  @JsonValue('BIMONTHLY')
  bimonthly,
  @JsonValue('YEARLY')
  yearly,
}
