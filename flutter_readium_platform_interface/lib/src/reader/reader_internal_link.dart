import 'dart:convert';

import '../index.dart';

/// Fired when the reader follows an internal (in-publication) link, e.g. an
/// end-note, index entry or cross-reference.
///
/// Notify-only: the native toolkit has already decided to follow the link;
/// the event cannot veto or redirect it.
class InternalLinkEvent implements JSONable {
  const InternalLinkEvent({required this.target, this.from});

  factory InternalLinkEvent.fromJson(final Map<String, dynamic> map) {
    // Native sends the nested objects as JSON strings, but accept decoded
    // maps too.
    final targetJson = map['target'];
    final target = Link.fromJson(
      targetJson is String ? json.decode(targetJson) as Map<String, dynamic> : targetJson as Map<String, dynamic>?,
    );
    if (target == null) {
      throw ArgumentError(
        'InternalLinkEvent.fromJson: required field "target" is missing or unparsable',
      );
    }
    return InternalLinkEvent(
      from: Locator.fromJsonDynamic(map['from']),
      target: target,
    );
  }

  /// Reader position just before the jump. Null if the reader has no position yet.
  final Locator? from;

  /// Target of the link (href with fragment, as resolved by the toolkit).
  final Link target;

  @override
  Map<String, dynamic> toJson() => {
    if (from != null) 'from': from!.toJson(),
    'target': target.toJson(),
  };
}
