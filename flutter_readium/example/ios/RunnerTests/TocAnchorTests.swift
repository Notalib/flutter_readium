import XCTest
import ReadiumShared
@testable import flutter_readium

/// Newspaper-style ToC entries target a `<section>` that has no cue and is not yielded by the
/// ContentService; lookups anchor it at the first content element inside it. See ADR 0001.
final class TocAnchorTests: XCTestCase {

  private let tree = XhtmlIdTree(xhtml: Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml"><body>
      <section id="s1">
        <div><h2 id="h1">A</h2><p id="p1">a</p></div>
        <aside id="a1"><p id="p2">b</p></aside>
      </section>
      <section id="empty"><div id="d1"></div></section>
      <p id="p3">c</p>
    </body></html>
    """.utf8))

  private let content: Set<String> = ["h1", "p1", "p2", "p3"]

  func testContainerMapsToFirstContentDescendant() {
    XCTAssertEqual(tree.firstDescendant(of: "s1", in: content), "h1")
    XCTAssertEqual(tree.firstDescendant(of: "a1", in: content), "p2")
  }

  func testContainerWithoutContentAndUnknownIdAreUnmapped() {
    XCTAssertNil(tree.firstDescendant(of: "empty", in: content))
    XCTAssertNil(tree.firstDescendant(of: "missing", in: content))
  }

  func testDoesNotLeakPastContainerEnd() {
    // `d1` is the only descendant of `empty`; `p3` follows the section and must not match.
    XCTAssertNil(tree.firstDescendant(of: "empty", in: ["p3"]))
  }

  func testElementDoesNotMatchItself() {
    XCTAssertNil(tree.firstDescendant(of: "p1", in: content))
  }

  func testAnchorRewritesToFirstCueAtOrAfterElementAndPreservesMetadata() {
    let locator = Locator(href: URL(string: "page.xhtml")!, mediaType: .xhtml, title: "Heading",
                          locations: .init(fragments: ["empty"], progression: 0.4, position: 3))
    let result = tree.anchor(locator, textId: "empty", cueIds: content)
    XCTAssertEqual(result?.locations.fragments, ["p3"])
    XCTAssertEqual(result?.locations.cssSelector, "#p3")
    XCTAssertEqual(result?.href, locator.href)
    XCTAssertEqual(result?.title, "Heading")
    XCTAssertEqual(result?.locations.progression, 0.4)
    XCTAssertEqual(result?.locations.position, 3)
    XCTAssertEqual(locator.locations.fragments, ["empty"])
  }

  func testUnknownAnchorKeepsFallbackAndKnownElementAfterLastCueHasNoMatch() {
    let locator = Locator(href: URL(string: "page.xhtml")!, mediaType: .xhtml)
    XCTAssertEqual(tree.anchor(locator, textId: "missing", cueIds: content), locator)
    XCTAssertNil(tree.anchor(locator, textId: "empty", cueIds: ["h1"]))
  }

  func testAnchorPreservesExplicitTime() {
    let locator = Locator(href: URL(string: "page.xhtml")!, mediaType: .xhtml,
                          locations: .init(fragments: ["empty", "t=2.5"]))
    XCTAssertEqual(tree.anchor(locator, textId: "empty", cueIds: content), locator)
  }

  func testParseErrorKeepsIdsReadBeforeIt() {
    let broken = XhtmlIdTree(xhtml: Data(#"<html><body><section id="s"><p id="p">x</p><br></section>"#.utf8))
    XCTAssertEqual(broken.firstDescendant(of: "s", in: ["p"]), "p")
  }
}

final class TocEntryIndexTests: XCTestCase {
  private let content = ["#h", "#p1", "#p2", "#p3"]
  private let anchors = ["#sec": "#h", "#side": "#p2", "#sec2": "#p3"]

  private func owner(_ selector: String, _ toc: [String]) -> Int? {
    tocEntryIndexFor(cssSelector: selector, contentSelectors: content, tocSelectors: toc, tocAnchors: anchors)
  }

  func testUncuedTargetsOwnTheirContentDescendants() {
    XCTAssertEqual(owner("#h", ["#sec", "#side", "#sec2"]), 0)
    XCTAssertEqual(owner("#p1", ["#sec", "#side", "#sec2"]), 0)
    XCTAssertEqual(owner("#p2", ["#sec", "#side", "#sec2"]), 1)
    XCTAssertEqual(owner("#p3", ["#sec", "#side", "#sec2"]), 2)
  }

  func testDeeperEntryWinsASharedStart() {
    XCTAssertEqual(owner("#h", ["#sec", "#h"]), 1)
  }

  func testPreludeWithoutFileEntryHasNoOwner() {
    XCTAssertNil(owner("#h", ["#side", "#sec2"]))
  }

  func testFileOnlyEntryOwnsPrelude() {
    XCTAssertEqual(owner("#h", ["#", "#p2"]), 0)
    XCTAssertEqual(owner("#p3", ["#", "#p2"]), 1)
  }

  func testUnresolvedEntryDoesNotOwnLaterCues() {
    XCTAssertEqual(owner("#p3", ["#sec", "#empty"]), 0)
    XCTAssertNil(owner("#p3", ["#empty"]))
  }

  func testUnknownSelectorUsesDocumentStart() {
    XCTAssertEqual(owner("#missing", ["#sec", "#sec2"]), 0)
  }

  func testNoEntriesHaveNoOwner() {
    XCTAssertNil(owner("#p1", []))
  }
}
