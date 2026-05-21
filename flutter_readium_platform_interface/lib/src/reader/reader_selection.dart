import '../index.dart';

/// Fired when the user selects text in the reader.
class TextSelectionEvent implements JSONable {
  const TextSelectionEvent({required this.locator, this.selectedText});

  factory TextSelectionEvent.fromJson(final Map<String, dynamic> map) {
    final locatorJson = map['locator'] as Map<String, dynamic>?;
    return TextSelectionEvent(
      locator: Locator.fromJson(locatorJson)!,
      selectedText: map['selectedText'] as String?,
    );
  }

  /// Location of the selection in the publication.
  final Locator locator;

  /// The selected text content, if available.
  final String? selectedText;

  @override
  Map<String, dynamic> toJson() => {
        'locator': locator.toJson(),
        if (selectedText != null) 'selectedText': selectedText,
      };
}

/// Fired when the user taps a configured editing action on selected text.
class SelectionActionEvent implements JSONable {
  const SelectionActionEvent({required this.actionId, required this.locator, this.selectedText});

  factory SelectionActionEvent.fromJson(final Map<String, dynamic> map) {
    final locatorJson = map['locator'] as Map<String, dynamic>?;
    return SelectionActionEvent(
      actionId: map['actionId'] as String,
      locator: Locator.fromJson(locatorJson)!,
      selectedText: map['selectedText'] as String?,
    );
  }

  /// The ID of the action that was tapped (matches [SelectionAction.id]).
  final String actionId;

  /// Location of the selection in the publication.
  final Locator locator;

  /// The selected text content, if available.
  final String? selectedText;

  @override
  Map<String, dynamic> toJson() => {
        'actionId': actionId,
        'locator': locator.toJson(),
        if (selectedText != null) 'selectedText': selectedText,
      };
}

/// Defines a native context menu item shown when text is selected.
///
/// Pass a list of these to [ReadiumReaderWidget.selectionActions] to configure
/// the native selection menu. Maximum 5 actions are supported on iOS.
class SelectionAction implements JSONable {
  const SelectionAction({required this.id, required this.title});

  factory SelectionAction.fromJson(final Map<String, dynamic> map) => SelectionAction(
        id: map['id'] as String,
        title: map['title'] as String,
      );

  /// Unique identifier for this action, returned in [SelectionActionEvent.actionId].
  final String id;

  /// Localized title displayed in the native context menu.
  final String title;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'title': title};
}
