import Foundation
import ReadiumShared

/// Wraps `HTMLResourceContentIterator.Factory` and handles EPUB page-break elements for TTS.
///
/// When `skipPageBreaks` is `true` (default), page-break elements are silently skipped.
/// When `false`, the raw label text from the element is rewritten to a localized string
/// (e.g. "Page 42" / "side 42"), derived from the publication's declared language.
///
/// Page-break elements are identified by matching the element's CSS selector against
/// the fragment IDs declared in the publication's pageList nav.
final class PageBreakSkippingContentIteratorFactory: ResourceContentIteratorFactory {
    var skipPageBreaks: Bool = true

    private let delegate: ResourceContentIteratorFactory

    init(delegate: ResourceContentIteratorFactory = HTMLResourceContentIterator.Factory()) {
        self.delegate = delegate
    }

    func make(
        publication: Publication,
        readingOrderIndex: Int,
        resource: Resource,
        locator: Locator
    ) -> ContentIterator? {
        guard let inner = delegate.make(
            publication: publication,
            readingOrderIndex: readingOrderIndex,
            resource: resource,
            locator: locator
        ) else { return nil }

        let pageBreakIds = publication.manifest.pageBreakIds()
        guard !pageBreakIds.isEmpty else { return inner }

        return PageBreakHandlingIterator(
            delegate: inner,
            pageBreakIds: pageBreakIds,
            shouldSkip: { [weak self] in self?.skipPageBreaks ?? true },
            pageLabel: publication.manifest.pageLabel()
        )
    }
}

private extension Manifest {
    func pageBreakIds() -> Set<String> {
        guard let links = subcollections["pageList"]?.first?.links else {
            return []
        }
        return Set(links.compactMap { link -> String? in
            guard let fragment = URL(string: link.href)?.fragment,
                  !fragment.isEmpty else { return nil }
            return fragment
        })
    }

    static let pageLabelFormats: [String: String] = [
        "en": "Page {label}",
        "da": "side {label}",
        "sv": "sida {label}",
        "no": "side {label}",
        "is": "{label}. síða",
    ]

    func pageLabel() -> ((String) -> String)? {
        guard let lang = metadata.languages.first else { return nil }
        let base = lang.components(separatedBy: "-").first?.lowercased() ?? lang.lowercased()
        guard let format = Self.pageLabelFormats[base] else { return nil }
        return { label in format.replacingOccurrences(of: "{label}", with: label) }
    }
}

private final class PageBreakHandlingIterator: ContentIterator {
    private let delegate: ContentIterator
    private let pageBreakIds: Set<String>
    private let shouldSkip: () -> Bool
    private let pageLabel: ((String) -> String)?

    init(
        delegate: ContentIterator,
        pageBreakIds: Set<String>,
        shouldSkip: @escaping () -> Bool,
        pageLabel: ((String) -> String)?
    ) {
        self.delegate = delegate
        self.pageBreakIds = pageBreakIds
        self.shouldSkip = shouldSkip
        self.pageLabel = pageLabel
    }

    func next() async throws -> ContentElement? {
        while let element = try await delegate.next() {
            if shouldSkip() && isPageBreak(element) { continue }
            return transform(element)
        }
        return nil
    }

    func previous() async throws -> ContentElement? {
        while let element = try await delegate.previous() {
            if shouldSkip() && isPageBreak(element) { continue }
            return transform(element)
        }
        return nil
    }

    private func transform(_ element: ContentElement) -> ContentElement {
        guard !shouldSkip(), let textElement = element as? TextContentElement else { return element }
        guard isPageBreak(element) else { return element }
        guard let rawLabel = textElement.text?.trimmingCharacters(in: .whitespaces),
              !rawLabel.isEmpty else { return element }
        let label = pageLabel?(rawLabel) ?? rawLabel
        let newSegments = textElement.segments.enumerated().map { i, seg in
            TextContentElement.Segment(locator: seg.locator, text: i == 0 ? label : "", attributes: seg.attributes)
        }
        return TextContentElement(
            locator: textElement.locator,
            role: textElement.role,
            segments: newSegments,
            attributes: textElement.attributes
        )
    }

    private func isPageBreak(_ element: ContentElement) -> Bool {
        guard let textElement = element as? TextContentElement else { return false }
        guard let selector = textElement.locator.locations.cssSelector,
              selector.hasPrefix("#") else { return false }
        return pageBreakIds.contains(String(selector.dropFirst()))
    }
}
