package dk.nota.flutterreadium

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.html.cssSelector

/** Serializes owner enrichment and delivery, including cues that need no enrichment. */
internal class OrderedLocatorEmitter(
    private val enrich: suspend (Locator) -> Locator,
    private val onLocator: (Locator, Link?) -> Unit,
) {
    private val mutex = Mutex()

    suspend fun emit(
        locator: Locator,
        readingOrderLink: Link?,
    ) {
        mutex.withLock {
            val enriched =
                if (locator.locations.tocHref == null && locator.locations.cssSelector != null) {
                    enrich(locator)
                } else {
                    locator
                }
            onLocator(enriched, readingOrderLink)
        }
    }
}
