import Combine
import ReadiumShared

public protocol TimebasedListener {
  func timebasedNavigator(_: FlutterTimeBasedNavigator, didChangeState state: ReadiumTimebasedState)
  func timebasedNavigator(_: FlutterTimeBasedNavigator, encounteredError error: Error)
  func timebasedNavigator(_: FlutterTimeBasedNavigator, reachedLocator locator: Locator, readingOrderLink: Link?)
  func timebasedNavigator(_: FlutterTimeBasedNavigator, requestsHighlightChangeAt locator: Locator?, withWordLocator wordLocator: Locator?)
}

public protocol FlutterTimeBasedNavigator
{
  var publication: Publication { get }
  var initialLocator: Locator? { get }
  var listener: TimebasedListener? { get set }
  
  // Current Locator which should be sent back over the bridge to Flutter.
  //var currentLocator: PassthroughSubject<Locator, Never> { get }
  
  func initNavigator() -> Void
  func setupNavigatorListeners() -> Void
  func dispose() -> Void
  func play() async -> Void
  func play(fromLocator: Locator) async -> Void
  func pause() async -> Void
  func resume() async -> Void
  func seek(toLocator: Locator) async -> Void
}
