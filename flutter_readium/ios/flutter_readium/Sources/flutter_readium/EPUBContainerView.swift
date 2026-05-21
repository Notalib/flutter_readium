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
/// Action methods are registered dynamically at runtime using `class_addMethod`,
/// so there is no compile-time limit on the number of custom actions.
class EPUBContainerView: UIView {
  weak var readerView: EPUBReaderView?

  /// The action IDs configured from Dart.
  private(set) var actionIds: [String] = []

  /// Mapping from registered selector name → action ID for dispatch.
  private var selectorToActionId: [String: String] = [:]

  /// The set of selectors registered for custom actions.
  private var registeredSelectors: Set<Selector> = []

  /// Configures the action slots with the given action definitions.
  /// Registers one ObjC method per action on this class at runtime.
  func configureActions(_ actions: [(id: String, title: String)]) {
    actionIds = actions.map { $0.id }
    actionTitles = actions.map { $0.title }
    selectorToActionId.removeAll()
    registeredSelectors.removeAll()

    for action in actions {
      let selectorName = "_frAction_\(action.id):"
      let selector = NSSelectorFromString(selectorName)
      selectorToActionId[selectorName] = action.id
      registeredSelectors.insert(selector)

      // Use class_replaceMethod so the IMP is always fresh for this instance.
      // The first block argument is the ObjC message receiver — the actual
      // EPUBContainerView that received the action — not a captured reference.
      // This is critical: if we captured [weak self] instead, the IMP would
      // silently no-op when a second publication is opened (new instance, old IMP).
      let imp = imp_implementationWithBlock(({ (receiver: AnyObject, _: Any?) in
        (receiver as? EPUBContainerView)?.handleAction(selectorName: selectorName)
      } as @convention(block) (AnyObject, Any?) -> Void))
      class_replaceMethod(type(of: self), selector, imp, "v@:@")
    }
  }

  /// Returns the `EditingAction` instances for the configured actions.
  func editingActions() -> [EditingAction] {
    return actionIds.enumerated().compactMap { index, id in
      guard let title = actionTitle(at: index) else { return nil }
      let selectorName = "_frAction_\(id):"
      let selector = NSSelectorFromString(selectorName)
      return EditingAction(title: title, action: selector)
    }
  }

  private var actionTitles: [String] = []

  private func actionTitle(at index: Int) -> String? {
    guard index < actionTitles.count else { return nil }
    return actionTitles[index]
  }

  // MARK: - Responder chain

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if registeredSelectors.contains(action) {
      return true
    }
    return super.canPerformAction(action, withSender: sender)
  }

  // MARK: - Action dispatch

  private func handleAction(selectorName: String) {
    guard let actionId = selectorToActionId[selectorName] else { return }
    readerView?.handleSelectionAction(actionId: actionId)
  }
}
