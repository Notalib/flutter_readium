import 'package:meta/meta.dart';

/// A publication downloaded from a license document (`.lcpl`), with the license injected.
@immutable
class LcpAcquiredPublication {
  const LcpAcquiredPublication({
    required this.path,
    required this.fileName,
    required this.licenseId,
    this.mediaType,
    this.fileExtension,
  });

  factory LcpAcquiredPublication.fromJson(final Map<Object?, Object?> json) => LcpAcquiredPublication(
    path: json['path']! as String,
    fileName: json['fileName']! as String,
    licenseId: json['licenseId']! as String,
    mediaType: json['mediaType'] as String?,
    fileExtension: json['fileExtension'] as String?,
  );

  /// Absolute path of the publication, in a directory the plugin owns (see `acquirePublication`).
  final String path;

  /// Name the file has at [path], built from the license id and the format's file extension.
  final String fileName;

  /// Identifier of the license that protects the publication.
  final String licenseId;

  /// Media type of the downloaded package, for example `application/epub+zip`, when known.
  final String? mediaType;

  /// File extension of the format, without the dot, when known.
  final String? fileExtension;

  Map<String, Object?> toJson() => {
    'path': path,
    'fileName': fileName,
    'licenseId': licenseId,
    'mediaType': mediaType,
    'fileExtension': fileExtension,
  };

  @override
  String toString() => 'LcpAcquiredPublication(path: $path, licenseId: $licenseId, mediaType: $mediaType)';
}

/// The state a license status document reports.
enum LcpLicenseState {
  ready,
  active,
  revoked,
  returned,
  cancelled,
  expired;

  static LcpLicenseState? fromWire(final String? value) => LcpLicenseState.values.asNameMap()[value];
}

/// Read-only facts about a publication's LCP license.
@immutable
class LcpLicenseInfo {
  const LcpLicenseInfo({
    required this.licenseId,
    required this.provider,
    required this.issued,
    required this.updated,
    this.rightsStart,
    this.rightsEnd,
    this.copyLimit,
    this.printLimit,
    this.charactersToCopyLeft,
    this.pagesToPrintLeft,
    this.state,
    this.statusMessage,
    this.statusUpdated,
  });

  factory LcpLicenseInfo.fromJson(final Map<Object?, Object?> json) => LcpLicenseInfo(
    licenseId: json['licenseId']! as String,
    provider: json['provider']! as String,
    issued: DateTime.parse(json['issued']! as String),
    updated: DateTime.parse(json['updated']! as String),
    rightsStart: _date(json['rightsStart']),
    rightsEnd: _date(json['rightsEnd']),
    copyLimit: json['copyLimit'] as int?,
    printLimit: json['printLimit'] as int?,
    charactersToCopyLeft: json['charactersToCopyLeft'] as int?,
    pagesToPrintLeft: json['pagesToPrintLeft'] as int?,
    state: LcpLicenseState.fromWire(json['state'] as String?),
    statusMessage: json['statusMessage'] as String?,
    statusUpdated: _date(json['statusUpdated']),
  );

  /// Identifier of the license.
  final String licenseId;

  /// URI of the license provider.
  final String provider;

  /// When the license was first issued.
  final DateTime issued;

  /// When the license was last updated.
  final DateTime updated;

  /// Start of the period the license is valid for, when the license sets one.
  final DateTime? rightsStart;

  /// End of the period the license is valid for, when the license sets one.
  final DateTime? rightsEnd;

  /// Characters the license lets the user copy over its lifetime. Null means no limit.
  final int? copyLimit;

  /// Pages the license lets the user print over its lifetime. Null means no limit.
  final int? printLimit;

  /// Characters the user may still copy. Null means no limit.
  final int? charactersToCopyLeft;

  /// Pages the user may still print. Null means no limit.
  final int? pagesToPrintLeft;

  /// State from the license status document. Null when no status document was fetched.
  final LcpLicenseState? state;

  /// Message from the status document, meant for the user.
  final String? statusMessage;

  /// When the status document was last updated.
  final DateTime? statusUpdated;

  Map<String, Object?> toJson() => {
    'licenseId': licenseId,
    'provider': provider,
    'issued': issued.toIso8601String(),
    'updated': updated.toIso8601String(),
    'rightsStart': rightsStart?.toIso8601String(),
    'rightsEnd': rightsEnd?.toIso8601String(),
    'copyLimit': copyLimit,
    'printLimit': printLimit,
    'charactersToCopyLeft': charactersToCopyLeft,
    'pagesToPrintLeft': pagesToPrintLeft,
    'state': state?.name,
    'statusMessage': statusMessage,
    'statusUpdated': statusUpdated?.toIso8601String(),
  };

  static DateTime? _date(final Object? value) => value is String ? DateTime.tryParse(value) : null;

  @override
  String toString() => 'LcpLicenseInfo(licenseId: $licenseId, provider: $provider, state: $state)';
}
