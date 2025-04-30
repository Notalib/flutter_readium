import '../index.dart';

part 'subscription_contact_info.freezed.dart';
part 'subscription_contact_info.g.dart';

@freezedExcludeUnion
abstract class SubscriptionContactInfo with _$SubscriptionContactInfo {
  @r2JsonSerializable
  const factory SubscriptionContactInfo({
    final String? name,
    final String? phoneNumber,
    final String? emailAddress,
    final String? houseName,
    final String? streetAddress,
    final String? city,
    final String? zipCode,
    final String? isoCountry,
    final String? websiteURL,
  }) = _XSubscriptionContactInfo;

  factory SubscriptionContactInfo.fromJson(final Map<String, dynamic> json) =>
      _$SubscriptionContactInfoFromJson(json);
}
