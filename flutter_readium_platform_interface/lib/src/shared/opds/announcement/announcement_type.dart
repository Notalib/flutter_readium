import '../../index.dart';

enum AnnouncementType {
  info,
  warning,
  alert,
  @JsonValue('modal-alert')
  modalAlert,
  @JsonValue('modal-confirm')
  modalConfirm,
}

extension AnnouncementTypeExtension on AnnouncementType {
  bool get isInfo => name == AnnouncementType.info.name;
  bool get isWarning => name == AnnouncementType.warning.name;
  bool get isAlert => name == AnnouncementType.alert.name;
  bool get isModalAlert => name == AnnouncementType.modalAlert.name;
  bool get isModalConfirm => name == AnnouncementType.modalConfirm.name;
}
