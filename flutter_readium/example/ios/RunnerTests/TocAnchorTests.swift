import XCTest
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

  func testParseErrorKeepsIdsReadBeforeIt() {
    let broken = XhtmlIdTree(xhtml: Data(#"<html><body><section id="s"><p id="p">x</p><br></section>"#.utf8))
    XCTAssertEqual(broken.firstDescendant(of: "s", in: ["p"]), "p")
  }
}
