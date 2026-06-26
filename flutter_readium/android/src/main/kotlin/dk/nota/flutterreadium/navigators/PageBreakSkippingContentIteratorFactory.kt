package dk.nota.flutterreadium.navigators

import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.LocalizedString
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.PublicationServicesHolder
import org.readium.r2.shared.publication.html.cssSelector
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.publication.services.content.iterators.HtmlResourceContentIterator
import org.readium.r2.shared.publication.services.content.iterators.ResourceContentIteratorFactory
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.resource.Resource

/**
 * Wraps [HtmlResourceContentIterator.Factory] and handles EPUB page-break elements for TTS.
 *
 * Page-break elements are identified by matching the [Content.TextElement] CSS selector against
 * the fragment IDs declared in the publication's pageList nav. Block-level page-break elements
 * (the typical DAISY/Nordic EPUB3 form) carry the element's own ID as their CSS selector, so
 * the match is exact. Inline spans inside a paragraph are not filtered (their text is merged
 * into the parent block's element and not individually addressable at this level).
 *
 * When [skipPageBreaks] is `true` (default), page-break elements are removed from the iterator.
 * When `false`, they are kept but the label text from the original element is rewritten to a
 * localized string (e.g. "Page 42" or "side 42"), derived from the publication's declared
 * language. [skipPageBreaks] can be changed at any time; the change takes effect on the next
 * [Content.Iterator.hasNext] / [Content.Iterator.hasPrevious] call.
 */
@OptIn(ExperimentalReadiumApi::class)
class PageBreakSkippingContentIteratorFactory(
    var skipPageBreaks: Boolean = true,
    private val delegate: ResourceContentIteratorFactory = HtmlResourceContentIterator.Factory(),
) : ResourceContentIteratorFactory {
    override suspend fun create(
        manifest: Manifest,
        servicesHolder: PublicationServicesHolder,
        readingOrderIndex: Int,
        resource: Resource,
        mediaType: MediaType,
        locator: Locator,
    ): Content.Iterator? {
        val inner =
            delegate.create(manifest, servicesHolder, readingOrderIndex, resource, mediaType, locator)
                ?: return null

        val pageBreakIds = manifest.pageBreakIds()
        if (pageBreakIds.isEmpty()) return inner
        return PageBreakHandlingIterator(inner, pageBreakIds, ::skipPageBreaks, manifest.pageLabel())
    }

    private fun Manifest.pageBreakIds(): Set<String> =
        subcollections["pageList"]
            ?.firstOrNull()
            ?.links
            ?.mapNotNull { link ->
                link.href
                    .toString()
                    .substringAfter("#", "")
                    .takeIf { it.isNotBlank() }
            }?.toSet()
            ?: emptySet()

    private fun Manifest.pageLabel(): ((String) -> String)? {
        val format =
            PAGE_LABEL_FORMATS.getOrFallback(metadata.languages.firstOrNull()) ?: return null
        return { label -> format.string.replace("{label}", label) }
    }

    companion object {
        private val PAGE_LABEL_FORMATS =
            LocalizedString.fromStrings(
                mapOf(
                    "en" to "Page {label}",
                    "da" to "side {label}",
                    "sv" to "sida {label}",
                    "no" to "side {label}",
                    "is" to "{label}. síða",
                ),
            )
    }
}

@OptIn(ExperimentalReadiumApi::class)
private class PageBreakHandlingIterator(
    private val delegate: Content.Iterator,
    private val pageBreakIds: Set<String>,
    private val shouldPageElementsSkip: () -> Boolean,
    private val pageLabel: ((String) -> String)?,
) : Content.Iterator {
    private data class Pending(
        val element: Content.Element,
        val forward: Boolean,
    )

    private var pending: Pending? = null

    override suspend fun hasNext(): Boolean {
        pending?.let { if (it.forward) return true }
        pending = null
        while (delegate.hasNext()) {
            val element = delegate.next()
            if (!shouldPageElementsSkip() || !element.isPageBreak()) {
                pending = Pending(element, forward = true)
                return true
            }
        }
        return false
    }

    override fun next(): Content.Element =
        pending
            ?.takeIf { it.forward }
            ?.element
            ?.also { pending = null }
            ?.transform()
            ?: throw IllegalStateException(
                "Called next() without a successful call to hasNext() first",
            )

    override suspend fun hasPrevious(): Boolean {
        pending?.let { if (!it.forward) return true }
        pending = null
        while (delegate.hasPrevious()) {
            val element = delegate.previous()
            if (!shouldPageElementsSkip() || !element.isPageBreak()) {
                pending = Pending(element, forward = false)
                return true
            }
        }
        return false
    }

    override fun previous(): Content.Element =
        pending
            ?.takeIf { !it.forward }
            ?.element
            ?.also { pending = null }
            ?.transform()
            ?: throw IllegalStateException(
                "Called previous() without a successful call to hasPrevious() first",
            )

    private fun Content.Element.transform(): Content.Element {
        if (shouldPageElementsSkip() || !isPageBreak()) return this
        val textElement = this as Content.TextElement
        val rawLabel = textElement.segments.joinToString("") { it.text }.trim()
        if (rawLabel.isEmpty()) return this
        val label = pageLabel?.let { it(rawLabel) } ?: rawLabel
        return textElement.copy(
            segments =
                textElement.segments.mapIndexed { i, seg ->
                    if (i == 0) seg.copy(text = label) else seg.copy(text = "")
                },
        )
    }

    private fun Content.Element.isPageBreak(): Boolean {
        if (this !is Content.TextElement) return false
        val selector = locator.locations.cssSelector ?: return false
        return selector.startsWith("#") && selector.drop(1) in pageBreakIds
    }
}
