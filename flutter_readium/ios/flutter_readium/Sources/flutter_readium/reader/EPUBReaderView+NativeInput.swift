import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

/// The kind of input event whose dispatch triggered a navigation. Task-local, so it is scoped to
/// one awaited observer dispatch and cannot leak between overlapping events.
enum InputNavigationSource {
  case pointer
  case key

  @TaskLocal static var current: InputNavigationSource?
}

/// Navigator for the stock `DirectionalNavigationAdapter`: forwards to the real one and reports
/// each input-triggered turn's outcome. It always reports the input as handled, so a failed
/// edge turn never reaches later observers as a center tap.
@MainActor
final class InputNavigationProxy: @preconcurrency VisualNavigator {
  private weak var navigator: EPUBNavigatorViewController?
  private let willNavigate: () -> Void
  private let didNavigate: (_ moved: Bool, _ source: InputNavigationSource?) -> Void

  init(
    navigator: EPUBNavigatorViewController,
    willNavigate: @escaping () -> Void,
    didNavigate: @escaping (_ moved: Bool, _ source: InputNavigationSource?) -> Void
  ) {
    self.navigator = navigator
    self.willNavigate = willNavigate
    self.didNavigate = didNavigate
  }

  var publication: Publication { navigator!.publication }
  var currentLocation: Locator? { navigator?.currentLocation }
  var view: UIView! { navigator?.view }
  var presentation: VisualNavigatorPresentation { navigator!.presentation }

  func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool {
    await navigator?.go(to: locator, options: options) ?? false
  }

  func go(to link: Link, options: NavigatorGoOptions) async -> Bool {
    await navigator?.go(to: link, options: options) ?? false
  }

  func goForward(options: NavigatorGoOptions) async -> Bool {
    await turn { await $0.goForward(options: options) }
  }

  func goBackward(options: NavigatorGoOptions) async -> Bool {
    await turn { await $0.goBackward(options: options) }
  }

  @discardableResult
  func addObserver(_ observer: InputObserving) -> InputObservableToken {
    navigator?.addObserver(SourceScopedObserver(observer)) ?? InputObservableToken()
  }

  func removeObserver(_ token: InputObservableToken) {
    navigator?.removeObserver(token)
  }

  private func turn(_ navigate: (EPUBNavigatorViewController) async -> Bool) async -> Bool {
    guard let navigator else { return false }
    let source = InputNavigationSource.current
    willNavigate()
    let moved = await navigate(navigator)
    didNavigate(moved, source)
    return true
  }
}

/// Tags the dispatch of each event with its source for `InputNavigationProxy`.
@MainActor
private final class SourceScopedObserver: InputObserving {
  private let observer: InputObserving

  init(_ observer: InputObserving) {
    self.observer = observer
  }

  func didReceive(_ event: PointerEvent) async -> Bool {
    await InputNavigationSource.$current.withValue(.pointer) {
      await observer.didReceive(event)
    }
  }

  func didReceive(_ event: KeyEvent) async -> Bool {
    await InputNavigationSource.$current.withValue(.key) {
      await observer.didReceive(event)
    }
  }
}
