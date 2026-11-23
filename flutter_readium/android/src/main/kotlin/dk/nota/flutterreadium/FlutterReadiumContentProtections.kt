package dk.nota.flutterreadium

import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.readium.r2.shared.publication.protection.ContentProtection
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Public entry point for add-on plugins (e.g. an LCP package) to register extra
 * [ContentProtection]s. Registrations persist across rebuilds of core's `PublicationOpener`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
object FlutterReadiumContentProtections {
    private val factories = CopyOnWriteArrayList<() -> ContentProtection>()

    /**
     * Registers [factory]. It is re-run whenever core rebuilds its opener. Call once, during the
     * add-on's plugin registration.
     */
    fun register(factory: () -> ContentProtection) {
        factories.add(factory)
        ReadiumReader.invalidatePublicationOpener()
    }

    internal fun create(): List<ContentProtection> = factories.map { it() }
}
