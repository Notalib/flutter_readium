package dk.nota.flutterreadium.navigators

import org.readium.r2.shared.ExperimentalReadiumApi
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
 * Wraps [HtmlResourceContentIterator.Factory] and filters out EPUB page-break elements so TTS
 * never reads out page numbers.
 *
 * Page-break elements are identified by matching the [Content.TextElement] CSS selector against
 * the fragment IDs declared in the publication's pageList nav. Block-level page-break elements
 * (the typical DAISY/Nordic EPUB3 form) carry the element's own ID as their CSS selector, so
 * the match is exact. Inline spans inside a paragraph are not filtered (their text is merged
 * into the parent block's element and not individually addressable at this level).
 */
@OptIn(ExperimentalReadiumApi::class)
class PageBreakSkippingContentIteratorFactory(
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
        return if (pageBreakIds.isEmpty()) inner else PageBreakFilteringIterator(inner, pageBreakIds)
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
}

@OptIn(ExperimentalReadiumApi::class)
private class PageBreakFilteringIterator(
    private val delegate: Content.Iterator,
    private val pageBreakIds: Set<String>,
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
            if (!element.isPageBreak()) {
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
            ?: throw IllegalStateException(
                "Called next() without a successful call to hasNext() first",
            )

    override suspend fun hasPrevious(): Boolean {
        pending?.let { if (!it.forward) return true }
        pending = null
        while (delegate.hasPrevious()) {
            val element = delegate.previous()
            if (!element.isPageBreak()) {
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
            ?: throw IllegalStateException(
                "Called previous() without a successful call to hasPrevious() first",
            )

    private fun Content.Element.isPageBreak(): Boolean {
        if (this !is Content.TextElement) return false
        val selector = locator.locations.cssSelector ?: return false
        return selector.startsWith("#") && selector.drop(1) in pageBreakIds
    }
}
