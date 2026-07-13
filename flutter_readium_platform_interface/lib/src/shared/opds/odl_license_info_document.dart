import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../extensions/strings.dart';
import '../../utils/jsonable.dart';
import 'odl_license_metadata.dart';
import 'price.dart';

/// Status of an ODL 1.0 license, as returned in a License Info Document.
///
/// https://drafts.opds.io/odl-1.0.html
enum OdlLicenseStatus {
  preorder,
  available,
  unavailable;

  static OdlLicenseStatus? optFromString(String? value) => switch (value) {
    'preorder' => OdlLicenseStatus.preorder,
    'available' => OdlLicenseStatus.available,
    'unavailable' => OdlLicenseStatus.unavailable,
    _ => null,
  };
}

/// An active loan record embedded in an ODL 1.0 License Info Document.
///
/// https://drafts.opds.io/odl-1.0.html
@immutable
class OdlLoan with Equatable implements JSONable {
  const OdlLoan({required this.href, required this.id, required this.patronId, required this.expires});

  /// URL of the loan.
  final String href;

  /// Unique identifier of the loan.
  final String id;

  /// Identifier of the patron who holds the loan (JSON key: `patron_id`).
  final String patronId;

  /// When this loan expires.
  final DateTime expires;

  @override
  List<Object?> get props => [href, id, patronId, expires];

  @override
  Map<String, dynamic> toJson() => {}
    ..put('href', href)
    ..put('id', id)
    ..put('patron_id', patronId)
    ..put('expires', expires.toIso8601String());

  static OdlLoan? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final jsonObjects = Map<String, dynamic>.of(json);
    final href = jsonObjects.optNullableString('href', remove: true);
    final id = jsonObjects.optNullableString('id', remove: true);
    final patronId = jsonObjects.optNullableString('patron_id', remove: true);
    final expires = jsonObjects.optNullableString('expires', remove: true)?.iso8601ToDate();
    if (href == null || id == null || patronId == null || expires == null) {
      return null;
    }
    return OdlLoan(href: href, id: id, patronId: patronId, expires: expires);
  }

  static List<OdlLoan> fromJsonArray(dynamic json) {
    if (json is! List) return const [];
    return json.whereType<Map<String, dynamic>>().map(OdlLoan.fromJson).whereType<OdlLoan>().toList();
  }
}

/// Checkout availability counters in an ODL 1.0 License Info Document.
///
/// https://drafts.opds.io/odl-1.0.html
@immutable
class OdlCheckouts with Equatable implements JSONable {
  const OdlCheckouts({required this.left, required this.available, this.active = const []});

  /// Remaining checkouts allowed under this license.
  final int left;

  /// Currently available (not checked-out) copies.
  final int available;

  /// List of active loans.
  final List<OdlLoan> active;

  @override
  List<Object?> get props => [left, available, active];

  @override
  Map<String, dynamic> toJson() => {}
    ..put('left', left)
    ..put('available', available)
    ..putIterableIfNotEmpty('active', active);

  static OdlCheckouts? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final jsonObjects = Map<String, dynamic>.of(json);
    final left = jsonObjects.optPositiveInt('left', remove: true);
    final available = jsonObjects.optPositiveInt('available', remove: true);
    if (left == null || available == null) return null;
    return OdlCheckouts(left: left, available: available, active: OdlLoan.fromJsonArray(jsonObjects.remove('active')));
  }
}

/// An ODL 1.0 License Info Document — the JSON document returned at the
/// license status URL embedded in an OPDS 2.0 feed.
///
/// Required fields: [identifier], [status], [checkouts].
/// Returns null from [fromJson] if any required field is missing.
///
/// https://drafts.opds.io/odl-1.0.html
@immutable
class OdlLicenseInfoDocument with Equatable implements JSONable {
  const OdlLicenseInfoDocument({
    required this.identifier,
    required this.status,
    required this.checkouts,
    this.format,
    this.created,
    this.terms,
    this.protection,
    this.price,
    this.source,
  });

  /// Unique URI identifying this license.
  final String identifier;

  /// Current status of the license.
  final OdlLicenseStatus status;

  /// Checkout counters and active loans.
  final OdlCheckouts checkouts;

  /// MIME type of the publication.
  final String? format;

  /// Timestamp when the license was issued.
  final DateTime? created;

  /// Checkout terms, if any.
  final OdlTerms? terms;

  /// DRM protection info, if any.
  final OdlProtection? protection;

  /// Purchase price of this license.
  final Price? price;

  /// URI of the license source.
  final String? source;

  @override
  List<Object?> get props => [identifier, status, checkouts, format, created, terms, protection, price, source];

  @override
  Map<String, dynamic> toJson() => {}
    ..put('identifier', identifier)
    ..put('status', status.name)
    ..put('checkouts', checkouts.toJson())
    ..putOpt('format', format)
    ..putOpt('created', created?.toIso8601String())
    ..putJSONableIfNotEmpty('terms', terms)
    ..putJSONableIfNotEmpty('protection', protection)
    ..putJSONableIfNotEmpty('price', price)
    ..putOpt('source', source);

  static OdlLicenseInfoDocument? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final jsonObjects = Map<String, dynamic>.of(json);
    final identifier = jsonObjects.optNullableString('identifier', remove: true);
    final status = OdlLicenseStatus.optFromString(jsonObjects.optNullableString('status', remove: true));
    final checkouts = OdlCheckouts.fromJson(jsonObjects.optJsonObject('checkouts', remove: true));
    if (identifier == null || status == null || checkouts == null) return null;
    return OdlLicenseInfoDocument(
      identifier: identifier,
      status: status,
      checkouts: checkouts,
      format: jsonObjects.optNullableString('format', remove: true),
      created: jsonObjects.optNullableString('created', remove: true)?.iso8601ToDate(),
      terms: OdlTerms.fromJson(jsonObjects.optJsonObject('terms', remove: true)),
      protection: OdlProtection.fromJson(jsonObjects.optJsonObject('protection', remove: true)),
      price: Price.fromJson(jsonObjects.optJsonObject('price', remove: true)),
      source: jsonObjects.optNullableString('source', remove: true),
    );
  }
}
