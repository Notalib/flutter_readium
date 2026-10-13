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


final class FlutterMediaOverlayTocTests: XCTestCase {
  private func parse(_ narration: String, toc: [String]) -> FlutterMediaOverlay {
    let json = try! JSONSerialization.jsonObject(with: Data(narration.utf8)) as! [String: Any]
    return FlutterMediaOverlay.fromJson(json, atPosition: 2, readingOrderDuration: 20, tocHrefs: toc)!
  }

  func testAudioLessParentOwnsNarratedChildren() {
    let overlay = parse("""
      {"narration":[{"text":"ch.xhtml#section","narration":[
        {"text":"ch.xhtml#heading","audio":"ch.mp3#t=0,5"},
        {"text":"ch.xhtml#p1","audio":"ch.mp3#t=5,10"}
      ]}]}
      """, toc: ["ch.xhtml#section"])
    XCTAssertEqual(overlay.items.map { $0.tocHref }, ["ch.xhtml#section", "ch.xhtml#section"])
    XCTAssertEqual(overlay.items.map { $0.position }, [2, 2])
    XCTAssertEqual(overlay.readingOrderDuration, 20)
  }

  func testSyntheticSubsectionHeadingContinuesOverParent() {
    let overlay = parse("""
      {"narration":[{"text":"ch.xhtml#chapter","narration":[
        {"text":"ch.xhtml#intro","audio":"ch.mp3#t=0,5"},
        {"text":"ch.xhtml#sub","audio":"ch.mp3#t=5,10"},
        {"text":"ch.xhtml#p1","audio":"ch.mp3#t=10,15"}
      ]}]}
      """, toc: ["ch.xhtml#chapter", "ch.xhtml#sub"])
    XCTAssertEqual(overlay.items.map { $0.tocHref }, ["ch.xhtml#chapter", "ch.xhtml#sub", "ch.xhtml#sub"])
  }

  func testFlatHeadingContinuesInsideGenericWrapper() {
    let overlay = parse("""
      {"narration":[{"text":"ch.xhtml#body","narration":[
        {"text":"ch.xhtml#heading","audio":"ch.mp3#t=0,5"},
        {"text":"ch.xhtml#p1","audio":"ch.mp3#t=5,10"}
      ]}]}
      """, toc: ["ch.xhtml#heading"])
    XCTAssertEqual(overlay.items.map { $0.tocHref }, ["ch.xhtml#heading", "ch.xhtml#heading"])
  }

  func testBoundaryPageUsesNextResourcesFileOnlyToc() {
    let overlay = parse("""
      {"narration":[{"text":"one.xhtml","narration":[
        {"text":"one.xhtml#p1","audio":"one.mp3#t=0,5"},
        {"text":"two.xhtml#page-3","audio":"two.mp3#t=0,1"}
      ]}]}
      """, toc: ["one.xhtml", "two.xhtml"])
    XCTAssertEqual(overlay.items.map { $0.tocHref }, ["one.xhtml", "two.xhtml"])
    XCTAssertEqual(overlay.items.last?.audioStart, 0)
  }

  func testUnknownNextResourceDoesNotInheritPreviousSection() {
    let overlay = parse("""
      {"narration":[{"text":"one.xhtml#section","narration":[
        {"text":"one.xhtml#p1","audio":"one.mp3#t=0,5"},
        {"text":"two.xhtml#page-3","audio":"two.mp3#t=0,1"}
      ]}]}
      """, toc: ["one.xhtml#section"])
    XCTAssertEqual(overlay.items.first?.tocHref, "one.xhtml#section")
    XCTAssertNil(overlay.items.last?.tocHref)
  }

  func testNestedListDoesNotReplaceCallersHeading() {
    let overlay = parse("""
      {"narration":[{"text":"ch.xhtml#chapter","narration":[
        {"text":"ch.xhtml#sub","narration":[{"text":"ch.xhtml#p1","audio":"ch.mp3#t=0,5"}]},
        {"text":"ch.xhtml#p2","audio":"ch.mp3#t=5,10"}
      ]}]}
      """, toc: ["ch.xhtml#chapter", "ch.xhtml#sub"])
    XCTAssertEqual(overlay.items.map { $0.tocHref }, ["ch.xhtml#sub", "ch.xhtml#chapter"])
  }

  func testKnownSectionSeeksAfterEarlierCueWithFallbackDisabled() {
    let overlay = parse("""
      {"narration":[
        {"text":"ch.xhtml#intro","audio":"ch.mp3#t=0,5"},
        {"text":"ch.xhtml#section","narration":[{"text":"ch.xhtml#heading","audio":"ch.mp3#t=5,10"}]}
      ]}
      """, toc: ["ch.xhtml#section"])
    let item = overlay.itemFromLocator(htmlLocator(href: "ch.xhtml", fragment: "section"), allowResourceFallback: false)
    XCTAssertEqual(item?.textId, "heading")
    XCTAssertEqual(item?.audioStart, 5)
    XCTAssertNil(overlay.itemFromLocator(htmlLocator(href: "ch.xhtml", fragment: "unknown"), allowResourceFallback: false))
  }

  func testRepeatedAnchorsMatchTheActualTextResource() {
    let overlay = makeOverlay([
      makeItem(audio: "one.mp3#t=0,5", text: "one.xhtml#heading"),
      makeItem(audio: "two.mp3#t=0,5", text: "two.xhtml#heading")
    ])
    let item = overlay.itemFromLocator(htmlLocator(href: "two.xhtml", fragment: "heading"), allowResourceFallback: false)
    XCTAssertEqual(item?.audioFile, "two.mp3")
  }

  func testExplicitTimeWinsOverSectionAnchor() {
    let overlay = makeOverlay([
      FlutterMediaOverlayItem(audio: "ch.mp3#t=0,5", text: "ch.xhtml#p1", position: 0, tocHref: "ch.xhtml#section"),
      FlutterMediaOverlayItem(audio: "ch.mp3#t=5,10", text: "ch.xhtml#p2", position: 0, tocHref: "ch.xhtml#section")
    ])
    let locator = Locator(href: URL(string: "ch.xhtml")!, mediaType: .xhtml, locations: .init(fragments: ["#section", "t=5"]))
    XCTAssertEqual(overlay.itemFromLocator(locator, allowResourceFallback: false)?.textId, "p2")
  }

  func testTitleEnrichmentDoesNotReopenOwnershipWindow() {
    let overlay = parse("""
      {"narration":[
        {"text":"ch.xhtml#chapter","narration":[
          {"text":"ch.xhtml#sub","audio":"ch.mp3#t=0,5"},
          {"text":"ch.xhtml#p1","audio":"ch.mp3#t=5,10"}
        ]},
        {"text":"ch.xhtml#outside","audio":"ch.mp3#t=10,15"}
      ]}
      """, toc: ["ch.xhtml#chapter", "ch.xhtml#sub"])
    let enriched = overlay.withTocTitles([Link(href: "ch.xhtml#sub", title: "Subsection")])
    XCTAssertEqual(enriched.items.map { $0.tocHref }, ["ch.xhtml#sub", "ch.xhtml#sub", nil])
    XCTAssertEqual(enriched.items.map { $0.tocTitle }, ["Subsection", "Subsection", nil])
    XCTAssertEqual(enriched.readingOrderDuration, 20)
  }

  func testExactCueWinsOverEarlierOwnedCue() {
    let overlay = makeOverlay([
      FlutterMediaOverlayItem(audio: "ch.mp3#t=0,5", text: "ch.xhtml#p1", position: 0, tocHref: "ch.xhtml#section"),
      FlutterMediaOverlayItem(audio: "ch.mp3#t=5,10", text: "ch.xhtml#section", position: 0)
    ])
    XCTAssertEqual(overlay.itemFromLocator(htmlLocator(href: "ch.xhtml", fragment: "section"), allowResourceFallback: false)?.audioStart, 5)
  }
}
