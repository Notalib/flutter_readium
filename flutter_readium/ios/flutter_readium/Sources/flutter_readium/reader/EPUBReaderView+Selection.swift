import ReadiumNavigator
import ReadiumShared

/// `SelectableNavigatorDelegate` conformance and selection-driven action handling.
extension EPUBReaderView {

  public func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
    Log.reader.debug("shouldShowMenuForSelection: \(selection.locator)")
    let locator = selection.locator
    let selectedText = locator.text.highlight
    channel.onTextSelected(locator: locator, selectedText: selectedText)
    // Return true to also show the native context menu with editing actions.
    return true
  }

  public func navigator(_ navigator: SelectableNavigator, canPerformAction action: EditingAction, for selection: Selection) -> Bool {
    return true
  }

  /// Called by `EPUBContainerView` when a configured action slot fires via the responder chain.
  func handleSelectionAction(actionId: String) {
    Log.reader.debug("handleSelectionAction: \(actionId)")
    guard let selection = readiumViewController.currentSelection else {
      Log.reader.warn("handleSelectionAction: no current selection")
      return
    }
    let locator = selection.locator
    let selectedText = locator.text.highlight
    channel.onSelectionAction(actionId: actionId, locator: locator, selectedText: selectedText)
  }

  func getCurrentSelection() -> Locator? {
    return self.readiumViewController.currentSelection?.locator
  }
}
