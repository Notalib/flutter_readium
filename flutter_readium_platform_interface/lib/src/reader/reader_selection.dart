import '../index.dart';

/// Fired when the user selects text in the reader.
class TextSelectionEvent implements JSONable {
  const TextSelectionEvent({required this.locator, this.selectedText});

  factory TextSelectionEvent.fromJson(final Map<String, dynamic> map) {
    final locatorJson = map['locator'] as Map<String, dynamic>?;
    return TextSelectionEvent(locator: Locator.fromJson(locatorJson)!, selectedText: map['selectedText'] as String?);
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
/// Pass a list of these to `ReadiumReaderWidget.selectionActions` to configure
/// the native selection menu. Maximum 5 actions are supported on iOS.
class SelectionAction implements JSONable {
  const SelectionAction({required this.id, required this.title});

  factory SelectionAction.fromJson(final Map<String, dynamic> map) =>
      SelectionAction(id: map['id'] as String, title: map['title'] as String);

  /// Unique identifier for this action, returned in [SelectionActionEvent.actionId].
  final String id;

  /// Localized title displayed in the native context menu.
  final String title;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'title': title};
}

/// System-provided text selection actions that can be shown or hidden.
///
/// Pass a set of these to `ReadiumReaderWidget.allowedDefaultActions` to control
/// which system actions appear alongside your custom [SelectionAction]s.
///
/// If `null` is passed (the default), all system defaults are shown.
/// If an empty set is passed, only your custom actions appear.
///
/// **Android limitation:** providing custom [SelectionAction]s replaces the
/// WebView's default `ActionMode.Callback` entirely, so system items (Copy,
/// Share, Select All) are not shown regardless of this setting.
/// `allowedDefaultActions` has no effect on Android.
enum DefaultSelectionAction {
  /// Copy selected text to clipboard.
  copy,

  /// Share selected text via system share sheet.
  share,

  /// Look up selected text in dictionary.
  ///
  /// On iOS 16+, enabling this also shows a "Search Web" button — both items
  /// are bundled in the same system menu group and cannot be separated.
  ///
  /// Not available on Android.
  lookup,

  /// Translate selected text. iOS 15+ only, not available on Android.
  translate,

  /// Select all content in the current view. Android only, no effect on iOS.
  selectAll;

  String get serialized => name;

  static DefaultSelectionAction? fromString(String value) {
    for (final action in values) {
      if (action.name == value) return action;
    }
    return null;
  }
}
