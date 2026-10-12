import XCTest
import ReadiumShared
@testable import flutter_readium

private func makeItem(audio: String, text: String, position: Int = 0) -> FlutterMediaOverlayItem {
  FlutterMediaOverlayItem(audio: audio, text: text, position: position)
}

private func makeOverlay(_ items: [FlutterMediaOverlayItem]) -> FlutterMediaOverlay {
  FlutterMediaOverlay(items: items, readingOrderDuration: nil)
}

private func htmlLocator(href: String, fragment: String? = nil) -> Locator {
  // Use a #-prefixed fragment so Locator.textId picks it up via
  // `locations.fragments.first(where: { $0.hasPrefix("#") })`.
  let frags: [String] = fragment.map { ["#\($0)"] } ?? []
  return Locator(
    href: URL(string: href)!,
    mediaType: MediaType.xhtml,
    locations: .init(fragments: frags)
  )
}

final class FlutterMediaOverlayTests: XCTestCase {

  private let overlay: FlutterMediaOverlay = {
    makeOverlay([
      makeItem(audio: "chap1.mp3#t=0,5",  text: "chap1.xhtml#p1"),
      makeItem(audio: "chap1.mp3#t=5,10", text: "chap1.xhtml#p2"),
      makeItem(audio: "chap2.mp3#t=0,8",  text: "chap2.xhtml#q1"),
    ])
  }()

  // MARK: Exact id match (always returns, regardless of flag)

  func testExactIdMatchReturnsItem() {
    let loc = htmlLocator(href: "chap1.xhtml", fragment: "p2")
    let item = overlay.itemFromLocator(loc, allowResourceFallback: false)
    XCTAssertEqual(item?.textId, "p2")
  }

  func testExactIdMatchUnaffectedByFallbackFlag() {
    let loc = htmlLocator(href: "chap1.xhtml", fragment: "p2")
    XCTAssertNotNil(overlay.itemFromLocator(loc, allowResourceFallback: true))
    XCTAssertNotNil(overlay.itemFromLocator(loc, allowResourceFallback: false))
  }

  // MARK: Unmatched id — gated fallback

  func testUnmatchedIdReturnsFirstItemWhenFallbackAllowed() {
    // ToC entry chap1.xhtml#title — "title" has no cue, cross-resource tap.
    let loc = htmlLocator(href: "chap1.xhtml", fragment: "title")
    let item = overlay.itemFromLocator(loc, allowResourceFallback: true)
    XCTAssertEqual(item?.textId, "p1")
  }

  func testUnmatchedIdReturnsNilWhenFallbackDisallowed() {
    // Same resource as currently playing — must not rewind.
    let loc = htmlLocator(href: "chap1.xhtml", fragment: "title")
    XCTAssertNil(overlay.itemFromLocator(loc, allowResourceFallback: false))
  }

  // MARK: No fragment on HTML resource — gated fallback

  func testNoFragmentReturnsFirstItemWhenFallbackAllowed() {
    let loc = htmlLocator(href: "chap1.xhtml")
    let item = overlay.itemFromLocator(loc, allowResourceFallback: true)
    XCTAssertEqual(item?.textId, "p1")
  }

  func testNoFragmentReturnsNilWhenFallbackDisallowed() {
    let loc = htmlLocator(href: "chap1.xhtml")
    XCTAssertNil(overlay.itemFromLocator(loc, allowResourceFallback: false))
  }

  // MARK: Wrong href — always nil

  func testWrongHrefReturnsNil() {
    let loc = htmlLocator(href: "chap3.xhtml", fragment: "p1")
    XCTAssertNil(overlay.itemFromLocator(loc, allowResourceFallback: true))
  }
}
