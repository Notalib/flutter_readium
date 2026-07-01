import UIKit
import ObjectiveC
import ReadiumNavigator
import ReadiumShared

/// A container view that participates in the UIKit responder chain, allowing
/// Readium's `EditingAction` selectors to be dispatched to it.
///
/// `EPUBReaderView` is an `NSObject` (not a `UIResponder`) and therefore cannot
/// receive actions via the responder chain. This custom `UIView` subclass sits
/// between the navigator's view and Flutter's view hierarchy, catching editing
/// action selectors and forwarding them to the `EPUBReaderView`.
///
/// Custom actions are identified by the selector name `_frAction_<id>:`. The
/// action ID is encoded directly in the selector, so no dispatch table is needed.
/// Methods are registered at runtime using `class_replaceMethod` so there is no
/// compile-time limit on the number of custom actions.
class EPUBContainerView: UIView {
  weak var readerView: EPUBReaderView?

  private static let selectorPrefix = "_frAction_"

  /// The action IDs configured from Dart.
  private(set) var actionIds: [String] = []
  private var actionTitles: [String] = []

  /// Configures the custom editing actions. Registers one ObjC method per action.
  func configureActions(_ actions: [(id: String, title: String)]) {
    actionIds = actions.map { $0.id }
    actionTitles = actions.map { $0.title }

    for action in actions {
      let selector = Self.selector(for: action.id)

      // Register the method on the class. The block receives the ObjC message
      // receiver as its first argument — the live EPUBContainerView instance —
      // so this works correctly across multiple publication loads.
      // No instance state is captured; the action ID is decoded from the selector.
      let imp = imp_implementationWithBlock({ (receiver: AnyObject, _: Any?) in
        (receiver as? EPUBContainerView)?.dispatchAction(for: selector)
      } as @convention(block) (AnyObject, Any?) -> Void)
      class_replaceMethod(Self.self, selector, imp, "v@:@")
    }
  }

  /// Returns `EditingAction` values to pass to Readium's navigator config.
  func editingActions() -> [EditingAction] {
    return actionIds.enumerated().compactMap { index, id in
      guard index < actionTitles.count else { return nil }
      return EditingAction(title: actionTitles[index], action: Self.selector(for: id))
    }
  }

  // MARK: - Responder chain

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if let actionId = Self.actionId(from: action) {
      return actionIds.contains(actionId)
    }
    return super.canPerformAction(action, withSender: sender)
  }

  // MARK: - Dispatch

  private func dispatchAction(for selector: Selector) {
    guard let actionId = Self.actionId(from: selector) else { return }
    readerView?.handleSelectionAction(actionId: actionId)
  }

  // MARK: - Selector helpers

  private static func selector(for actionId: String) -> Selector {
    NSSelectorFromString("\(selectorPrefix)\(actionId):")
  }

  private static func actionId(from selector: Selector) -> String? {
    let name = NSStringFromSelector(selector)
    guard name.hasPrefix(selectorPrefix) && name.hasSuffix(":") else { return nil }
    return String(name.dropFirst(selectorPrefix.count).dropLast())
  }
}
