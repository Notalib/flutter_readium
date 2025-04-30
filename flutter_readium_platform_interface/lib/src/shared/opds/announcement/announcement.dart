import '../../index.dart';

part 'announcement.freezed.dart';
part 'announcement.g.dart';

@freezedExcludeUnion
abstract class Announcement with _$Announcement {
  @r2JsonSerializable
  const factory Announcement({
    required final AnnouncementType type,
    final String? id,
    final String? title,
    final String? message,
    final String? actionUrl,
    @Default(false) final bool persistent,
    @dateTimeLocal final DateTime? activeFrom,
    @dateTimeLocal final DateTime? activeTo,
    final String? confirmText,
    final String? cancelText,

    /// True if announcement is dismissed by user action.
    @Default(false) final bool isDismissed,
  }) = _Announcement;

  factory Announcement.fromJson(final Map<String, dynamic> json) => _$AnnouncementFromJson(json);
}
