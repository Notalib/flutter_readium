import '../index.dart';

part 'subscription.freezed.dart';
part 'subscription.g.dart';

@freezedExcludeUnion
abstract class Subscription with _$Subscription {
  const factory Subscription({
    final SubscriptionFrequency? frequency,
    final int? frequencyCount,
    final String? frequencyCustomText,
    final SubscriptionContactInfo? contactInfo,
    final Price? price,
    @Default(false) final bool subscriptionNeeded,
    @Default(false) final bool hasSubscription,
  }) = _Subscription;

  factory Subscription.fromJson(final Map<String, dynamic> json) => _$SubscriptionFromJson(json);
}
