import Combine
import ReadiumShared

public protocol TimebasedListener {
  func timebasedNavigator(_: FlutterTimebasedNavigator, didChangeState state: ReadiumTimebasedState)
  func timebasedNavigator(_: FlutterTimebasedNavigator, encounteredError error: Error, withDescription description: String?)
  func timebasedNavigator(_: FlutterTimebasedNavigator, reachedLocator locator: Locator, segmentDuration: TimeInterval?)
  func timebasedNavigator(_: FlutterTimebasedNavigator, requestsHighlightAt locator: Locator?, withWordLocator wordLocator: Locator?)
}

public protocol FlutterTimebasedNavigator
{
  var publication: Publication { get }
  var initialLocator: Locator? { get }
  var currentLocator: Locator? { get }
  var listener: TimebasedListener? { get set }
  
  func initNavigator() async -> Void
  @MainActor
  func dispose() -> Void
  @MainActor
  func play(fromLocator: Locator?) async -> Void
  @MainActor
  func pause() async -> Void
  @MainActor
  func resume() async -> Void
  @MainActor
  func togglePlayPause() async -> Void
  @MainActor
  func seekForward() async -> Bool
  @MainActor
  func seekBackward() async -> Bool
  @MainActor
  func seek(toLocator: Locator) async -> Bool
  @MainActor
  func seek(toProgression: Double) async -> Bool
  @MainActor
  func seek(toOffset: Double) async -> Bool
  @MainActor
  func seekRelative(byOffsetSeconds: Double) async -> Bool
  /// Notify TimebasedNavigator that its decorations should be updated.
  @MainActor
  func decorationsUpdated() -> Void
}
