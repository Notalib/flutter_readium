import '../index.dart';

part 'x_rights.freezed.dart';
part 'x_rights.g.dart';

/// Nota Rights Property

@freezedExcludeUnion
abstract class XRights with _$XRights {
  @r2JsonSerializable
  const factory XRights({
    final List<XRightsEnum>? download,
    final List<XRightsEnum>? preview,
    final List<XRightsEnum>? sample,
  }) = _XRights;

  factory XRights.fromJson(final Map<String, dynamic> json) => _$XRightsFromJson(json);
}

enum XRightsEnum {
  @JsonValue('Anonymous')
  anonymous,
  @JsonValue('AphasCd')
  aphasCd,
  @JsonValue('BookShare')
  bookShare,
  @JsonValue('BrailleBk')
  brailleBk,
  @JsonValue('BrMusic')
  brMusic,
  @JsonValue('EAssist')
  bAssist,
  @JsonValue('EBookCd')
  eBookCd,
  @JsonValue('EBookDo')
  eBookDo,
  @JsonValue('EBookPreview')
  eBookPreview,
  @JsonValue('ExtendedSps')
  extendedSps,
  @JsonValue('Maneno')
  maneno,
  @JsonValue('Sps')
  sps,
  @JsonValue('TalkBkCd')
  talkBkCd,
  @JsonValue('TalkBkDo')
  talkBkDo,
  @JsonValue('TalkBkPreview')
  talkBkPreview,
  @JsonValue('Teacher')
  teacher,
}
