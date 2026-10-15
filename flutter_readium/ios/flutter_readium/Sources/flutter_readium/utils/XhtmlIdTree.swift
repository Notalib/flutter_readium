import Foundation

/// Element ids of an XHTML document in document order, with each element's subtree.
///
/// ToC entries can target a container (e.g. a newspaper `<section>` or `<aside>`) that has no
/// Sync Narration cue and that the ContentService never yields; only its descendants do. This
/// maps such a target to the first descendant that does. See ADR 0001.
struct XhtmlIdTree {
  let ids: [String]
  /// The descendants of `ids[i]` are `ids[(i + 1)..<subtreeEnd[i]]`.
  let subtreeEnd: [Int]

  /// Ids after an XML parse error are missing; elements still open then own every id read.
  init(xhtml data: Data) {
    let collector = Collector()
    let parser = XMLParser(data: data)
    parser.shouldResolveExternalEntities = false
    parser.delegate = collector
    if !parser.parse() {
      Log.toc.debug("XhtmlIdTree: XML parse stopped: \(String(describing: parser.parserError))")
    }
    for case let index? in collector.open {
      collector.subtreeEnd[index] = collector.ids.count
    }
    ids = collector.ids
    subtreeEnd = collector.subtreeEnd
  }

  /// The first id inside element `id`, excluding `id` itself, that is in `candidates`.
  func firstDescendant(of id: String, in candidates: Set<String>) -> String? {
    guard let start = ids.firstIndex(of: id) else { return nil }
    return ids[(start + 1)..<subtreeEnd[start]].first(where: candidates.contains)
  }

  private final class Collector: NSObject, XMLParserDelegate {
    var ids: [String] = []
    var subtreeEnd: [Int] = []
    /// Index into `ids` for each open element, or nil when it has no id.
    var open: [Int?] = []

    func parser(
      _ parser: XMLParser,
      didStartElement elementName: String,
      namespaceURI: String?,
      qualifiedName qName: String?,
      attributes attributeDict: [String: String] = [:]
    ) {
      if let id = attributeDict["id"] {
        open.append(ids.count)
        ids.append(id)
        subtreeEnd.append(ids.count)
      } else {
        open.append(nil)
      }
    }

    func parser(
      _ parser: XMLParser,
      didEndElement elementName: String,
      namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      if let index = open.popLast() ?? nil {
        subtreeEnd[index] = ids.count
      }
    }
  }
}
