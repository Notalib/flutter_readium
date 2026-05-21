import UIKit
import ReadiumNavigator
import ReadiumShared

/// Maximum number of configurable editing action slots.
private let maxActionSlots = 5

/// A container view that participates in the UIKit responder chain, allowing
/// Readium's `EditingAction` selectors to be dispatched to it.
///
/// `EPUBReaderView` is an `NSObject` (not a `UIResponder`) and therefore cannot
/// receive actions via the responder chain. This custom `UIView` subclass sits
/// between the navigator's view and Flutter's view hierarchy, catching editing
/// action selectors and forwarding them to the `EPUBReaderView`.
class EPUBContainerView: UIView {
  weak var readerView: EPUBReaderView?

  /// The action IDs configured from Dart, mapped by slot index.
  private(set) var actionIds: [String] = []

  /// Configures the action slots with the given action definitions.
  /// Configures the action slots with the given action definitions.
  func configureActions(_ actions: [(id: String, title: String)]) {
    actionIds = actions.prefix(maxActionSlots).map { $0.id }
    actionTitles = actions.prefix(maxActionSlots).map { $0.title }
  }

  /// Returns the `EditingAction` instances for the configured actions.
  func editingActions() -> [EditingAction] {
    let selectors: [Selector] = [
      #selector(selectionAction0(_:)),
      #selector(selectionAction1(_:)),
      #selector(selectionAction2(_:)),
      #selector(selectionAction3(_:)),
      #selector(selectionAction4(_:)),
    ]

    return actionIds.enumerated().compactMap { index, _ in
      guard index < selectors.count,
            let title = actionTitle(at: index) else { return nil }
      return EditingAction(title: title, action: selectors[index])
    }
  }

  private var actionTitles: [String] = []

  private func actionTitle(at index: Int) -> String? {
    guard index < actionTitles.count else { return nil }
    return actionTitles[index]
  }

  // MARK: - Responder chain

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    let actionSelectors: [Selector] = [
      #selector(selectionAction0(_:)),
      #selector(selectionAction1(_:)),
      #selector(selectionAction2(_:)),
      #selector(selectionAction3(_:)),
      #selector(selectionAction4(_:)),
    ]
    if actionSelectors.contains(action) {
      let index = actionSelectors.firstIndex(of: action)!
      return index < actionIds.count
    }
    return super.canPerformAction(action, withSender: sender)
  }

  // MARK: - Action slot methods

  @objc func selectionAction0(_ sender: Any?) { handleAction(index: 0) }
  @objc func selectionAction1(_ sender: Any?) { handleAction(index: 1) }
  @objc func selectionAction2(_ sender: Any?) { handleAction(index: 2) }
  @objc func selectionAction3(_ sender: Any?) { handleAction(index: 3) }
  @objc func selectionAction4(_ sender: Any?) { handleAction(index: 4) }

  private func handleAction(index: Int) {
    guard index < actionIds.count else { return }
    readerView?.handleSelectionAction(actionId: actionIds[index])
  }
}
