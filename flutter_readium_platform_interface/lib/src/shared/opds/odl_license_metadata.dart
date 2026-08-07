import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../extensions/strings.dart';
import '../../utils/jsonable.dart';
import 'price.dart';

/// Checkout terms embedded in an ODL 1.0 license.
///
/// All fields are optional; absent fields mean "unlimited / no constraint".
///
/// https://drafts.opds.io/odl-1.0.html
@immutable
class OdlTerms with Equatable implements JSONable {
  const OdlTerms({this.checkouts, this.expires, this.concurrency, this.length});

  /// Maximum total checkouts allowed for this license. Null means unlimited.
  final int? checkouts;

  /// Date on which the license expires. Null means no fixed expiry.
  final DateTime? expires;

  /// Maximum number of concurrent checkouts. Null means unlimited.
  final int? concurrency;

  /// Maximum duration of a single checkout, in seconds. Null means unlimited.
  final int? length;

  @override
  List<Object?> get props => [checkouts, expires, concurrency, length];

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('checkouts', checkouts)
    ..putOpt('expires', expires?.toIso8601String())
    ..putOpt('concurrency', concurrency)
    ..putOpt('length', length);

  static OdlTerms? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final jsonObjects = Map<String, dynamic>.of(json);
    return OdlTerms(
      checkouts: jsonObjects.optPositiveInt('checkouts', remove: true),
      expires: jsonObjects.optNullableString('expires', remove: true)?.iso8601ToDate(),
      concurrency: jsonObjects.optPositiveInt('concurrency', remove: true),
      length: jsonObjects.optPositiveInt('length', remove: true),
    );
  }
}

/// DRM protection constraints embedded in an ODL 1.0 license.
///
/// https://drafts.opds.io/odl-1.0.html
@immutable
class OdlProtection with Equatable implements JSONable {
  const OdlProtection({
    this.formats = const [],
    this.devices,
    this.copy = true,
    this.printAllowed = true,
    this.tts = true,
  });

  /// DRM format(s), e.g. `application/vnd.adobe.adept+xml`. Empty means unspecified.
  final List<String> formats;

  /// Maximum number of devices per checkout. Null means unlimited.
  final int? devices;

  /// Whether copying content is permitted (spec default: true).
  final bool copy;

  /// Whether printing is permitted (spec default: true).
  /// Named [printAllowed] to avoid shadowing the global `print` function.
  final bool printAllowed;

  /// Whether text-to-speech is permitted (spec default: true).
  final bool tts;

  @override
  List<Object?> get props => [formats, devices, copy, printAllowed, tts];

  /// Serializes format as a single string when only one value is present,
  /// matching the spec's "String or Array" definition.
  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{}
      ..put('copy', copy)
      ..put('print', printAllowed)
      ..put('tts', tts)
      ..putOpt('devices', devices);
    if (formats.length == 1) {
      json['format'] = formats.first;
    } else if (formats.isNotEmpty) {
      json['format'] = formats;
    }
    return json;
  }

  static OdlProtection? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final jsonObjects = Map<String, dynamic>.of(json);
    return OdlProtection(
      formats: jsonObjects.optStringsFromArrayOrSingle('format', remove: true),
      devices: jsonObjects.optPositiveInt('devices', remove: true),
      copy: jsonObjects.optBoolean('copy', fallback: true, remove: true),
      printAllowed: jsonObjects.optBoolean('print', fallback: true, remove: true),
      tts: jsonObjects.optBoolean('tts', fallback: true, remove: true),
    );
  }
}

/// Properties of an ODL 1.0 license, embedded in an OPDS 2.0 link's `properties`
/// object under the key `license`.
///
/// https://drafts.opds.io/odl-1.0.html
@immutable
class OdlLicenseMetadata with Equatable implements JSONable {
  const OdlLicenseMetadata({
    required this.identifier,
    required this.format,
    required this.created,
    this.terms,
    this.protection,
    this.price,
    this.source,
  });

  /// Unique URI identifying this license.
  final String identifier;

  /// MIME type of the publication (e.g. `application/epub+zip`).
  final String format;

  /// Timestamp when the license was issued.
  final DateTime created;

  /// Checkout terms, if any.
  final OdlTerms? terms;

  /// DRM protection info, if any.
  final OdlProtection? protection;

  /// Purchase price of this license.
  final Price? price;

  /// URI of the license source.
  final String? source;

  @override
  List<Object?> get props => [identifier, format, created, terms, protection, price, source];

  @override
  Map<String, dynamic> toJson() => {}
    ..put('identifier', identifier)
    ..put('format', format)
    ..put('created', created.toIso8601String())
    ..putJSONableIfNotEmpty('terms', terms)
    ..putJSONableIfNotEmpty('protection', protection)
    ..putJSONableIfNotEmpty('price', price)
    ..putOpt('source', source);

  /// Returns null if any required field ([identifier], [format], [created]) is missing.
  static OdlLicenseMetadata? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final jsonObjects = Map<String, dynamic>.of(json);
    final identifier = jsonObjects.optNullableString('identifier', remove: true);
    final format = jsonObjects.optNullableString('format', remove: true);
    final created = jsonObjects.optNullableString('created', remove: true)?.iso8601ToDate();
    if (identifier == null || format == null || created == null) return null;
    return OdlLicenseMetadata(
      identifier: identifier,
      format: format,
      created: created,
      terms: OdlTerms.fromJson(jsonObjects.optJsonObject('terms', remove: true)),
      protection: OdlProtection.fromJson(jsonObjects.optJsonObject('protection', remove: true)),
      price: Price.fromJson(jsonObjects.optJsonObject('price', remove: true)),
      source: jsonObjects.optNullableString('source', remove: true),
    );
  }
}
