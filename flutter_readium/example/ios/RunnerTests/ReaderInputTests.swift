import XCTest
import UIKit
@_spi(ExperimentalTargetElement) @testable import ReadiumNavigator
import ReadiumShared
@testable import flutter_readium

@MainActor
final class ReaderInputTests: XCTestCase {
  private static var nextViewIdentifier: Int64 = 281

  func testImageTapsTakePriorityOverPageTurnsAndControls() async {
    for x in [50.0, 200.0, 350.0] {
      let navigator = InputTestNavigator()
      var images = 0
      var toggles = 0
      let adapter = bindEPUBInput(to: navigator, onImage: { _, _ in images += 1; return true }, onCenterTap: { toggles += 1 })
      let image = ImageContentElement(
        locator: Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml),
        embeddedLink: Link(href: "image.png", mediaType: .png))

      await navigator.tap(x: x, image: image)

      XCTAssertEqual(images, 1)
      XCTAssertEqual(navigator.turns, 0)
      XCTAssertEqual(toggles, 0)
      withExtendedLifetime(adapter) {}
    }
  }

  func testOrdinaryTapsStillNavigateOrToggleControls() async {
    let navigator = InputTestNavigator()
    var toggles = 0
    let adapter = bindEPUBInput(to: navigator, onImage: { _, _ in XCTFail("Unexpected image action"); return false }, onCenterTap: { toggles += 1 })

    await navigator.tap(x: 350)
    XCTAssertEqual(navigator.turns, 1)
    XCTAssertEqual(toggles, 0)
    await navigator.tap(x: 200)
    XCTAssertEqual(navigator.turns, 1)
    XCTAssertEqual(toggles, 1)
    withExtendedLifetime(adapter) {}
  }

  func testIgnoredPageImagesStillAllowNavigationAndControls() async {
    let navigator = InputTestNavigator()
    var toggles = 0
    let adapter = bindEPUBInput(to: navigator, onImage: { _, _ in false }, onCenterTap: { toggles += 1 })
    let image = ImageContentElement(
      locator: Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml),
      embeddedLink: Link(href: "page.png", mediaType: .png))

    await navigator.tap(x: 350, image: image)
    XCTAssertEqual(navigator.turns, 1)
    XCTAssertEqual(toggles, 0)
    await navigator.tap(x: 200, image: image)
    XCTAssertEqual(navigator.turns, 1)
    XCTAssertEqual(toggles, 1)
    withExtendedLifetime(adapter) {}
  }

  func testStopClearsCueHeldDuringFailedNavigation() async throws {
    try await withReader { reader in
      reader.beginUserNavigation()
      _ = await reader.syncToLocator(self.cue, animated: false)
      XCTAssertNotNil(reader.suppressedSyncCue)

      reader.resetForNarrationStop()
      reader.finishUserNavigation(moved: false)

      XCTAssertNil(reader.suppressedSyncCue)
      XCTAssertNil(reader.pendingSyncReplay)
      XCTAssertNil(reader.lastSyncLocator)
      XCTAssertEqual(reader.userNavigationsInFlight, 0)
    }
  }

  func testStopCancelsReplayAlreadyQueuedByFailedNavigation() async throws {
    try await withReader { reader in
      reader.beginUserNavigation()
      _ = await reader.syncToLocator(self.cue, animated: false)
      reader.finishUserNavigation(moved: false)
      let replay = try XCTUnwrap(reader.pendingSyncReplay)

      reader.resetForNarrationStop()
      await replay.value

      XCTAssertTrue(replay.isCancelled)
      XCTAssertNil(reader.lastSyncLocator)
      XCTAssertNil(reader.suppressedSyncCue)
    }
  }

  private var cue: Locator {
    Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml, locations: .init(fragments: ["cue"]))
  }

  private func withReader(_ body: (EPUBReaderView) async throws -> Void) async throws {
    let registrar = try XCTUnwrap(FlutterReadiumPlugin.registrar)
    let previous = FlutterReadiumPlugin.instance
    let plugin = FlutterReadiumPlugin()
    plugin.currentPublication = inputTestPublication()
    FlutterReadiumPlugin.instance = plugin
    defer { FlutterReadiumPlugin.instance = previous }
    let viewIdentifier = Self.nextViewIdentifier
    Self.nextViewIdentifier += 1
    let reader = EPUBReaderView(
      frame: CGRect(x: 0, y: 0, width: 400, height: 800), viewIdentifier: viewIdentifier,
      arguments: ["pubIdentifier": "input-test"], registrar: registrar)
    defer {
      reader.channel.setMethodCallHandler(nil)
      reader.readiumViewController.delegate = nil
      plugin.clearCurrentReaderView(ifIs: reader)
    }
    try await body(reader)
  }
}

private func inputTestPublication() -> Publication {
  Publication(manifest: Manifest(metadata: Metadata(title: "Synthetic input test"), readingOrder: [Link(href: "chapter.xhtml", mediaType: .xhtml)]))
}

@MainActor
private final class InputTestNavigator: @preconcurrency VisualNavigator {
  let publication = inputTestPublication()
  let currentLocation: Locator? = nil
  let view: UIView! = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
  let presentation = VisualNavigatorPresentation(readingProgression: .ltr, scroll: false, axis: .horizontal)
  var turns = 0
  private var observers: [(InputObservableToken, InputObserving)] = []

  func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool { false }
  func go(to link: Link, options: NavigatorGoOptions) async -> Bool { false }
  func goForward(options: NavigatorGoOptions) async -> Bool { turns += 1; return true }
  func goBackward(options: NavigatorGoOptions) async -> Bool { turns += 1; return true }

  func addObserver(_ observer: InputObserving) -> InputObservableToken {
    let token = InputObservableToken()
    observers.append((token, observer))
    return token
  }

  func removeObserver(_ token: InputObservableToken) {
    observers.removeAll { $0.0 == token }
  }

  func tap(x: Double, image: ImageContentElement? = nil) async {
    let target = image.map { PointerEvent.TargetElement(frame: .zero, content: $0) }
    for phase in [PointerEvent.Phase.down, .up] {
      var event = PointerEvent(pointer: .touch(TouchPointer(id: 1)), phase: phase, location: CGPoint(x: x, y: 300), modifiers: [], targetElement: target)
      for (_, observer) in observers {
        if await observer.didReceive(event) { event.phase = .cancel }
      }
    }
  }
}
