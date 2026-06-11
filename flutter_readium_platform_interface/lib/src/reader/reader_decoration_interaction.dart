import '../index.dart';

/// The type of interaction with a decoration.
enum DecorationInteractionType {
  tap,
  longPress;

  static DecorationInteractionType fromString(String? value) {
    switch (value) {
      case 'longPress':
        return DecorationInteractionType.longPress;
      case 'tap':
      default:
        return DecorationInteractionType.tap;
    }
  }
}

/// Fired when the user interacts with an existing decoration (e.g. taps a highlight).
class DecorationInteractionEvent implements JSONable {
  const DecorationInteractionEvent({
    required this.decorationId,
    required this.group,
    required this.type,
    this.locator,
  });

  factory DecorationInteractionEvent.fromJson(final Map<String, dynamic> map) {
    final locatorJson = map['locator'] as Map<String, dynamic>?;
    return DecorationInteractionEvent(
      decorationId: map['decorationId'] as String,
      group: map['group'] as String,
      type: DecorationInteractionType.fromString(map['type'] as String?),
      locator: locatorJson != null ? Locator.fromJson(locatorJson) : null,
    );
  }

  /// The ID of the decoration that was interacted with.
  final String decorationId;

  /// The decoration group this decoration belongs to.
  final String group;

  /// The type of interaction (tap or long press).
  final DecorationInteractionType type;

  /// The locator of the decoration, if available.
  final Locator? locator;

  @override
  Map<String, dynamic> toJson() => {
    'decorationId': decorationId,
    'group': group,
    'type': type.name,
    if (locator != null) 'locator': locator!.toJson(),
  };
}
