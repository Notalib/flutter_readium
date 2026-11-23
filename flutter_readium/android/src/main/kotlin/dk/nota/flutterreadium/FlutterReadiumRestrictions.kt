package dk.nota.flutterreadium

import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.isRestricted
import org.readium.r2.shared.publication.services.protectionError
import java.util.concurrent.CopyOnWriteArrayList

/** An error with a caller-chosen wire code. Dart sees it as `ReadiumException.code` / `.message` / `.details`. */
data class FlutterReadiumCustomError(
    val code: String,
    val message: String,
    val data: Map<String, Any?>? = null,
)

/**
 * Lets add-on plugins explain why a publication opened restricted (e.g. an expired LCP license).
 * An open for reading fails with the first custom error a mapper returns, or with `forbidden` when
 * none does. Metadata-only loads still return the restricted publication.
 */
object FlutterReadiumRestrictions {
    private val mappers = CopyOnWriteArrayList<(Publication) -> FlutterReadiumCustomError?>()

    /**
     * Registers [mapper], called with the restricted publication. Return null for protections the
     * add-on does not own. Call once, during the add-on's plugin registration.
     */
    fun registerMapper(mapper: (Publication) -> FlutterReadiumCustomError?) {
        mappers.add(mapper)
    }

    internal fun customError(publication: Publication): FlutterReadiumCustomError? = mappers.firstNotNullOfOrNull { it(publication) }
}

/** The error to fail an open with when this publication is restricted, or null when it is readable. */
internal fun Publication.restrictionFailure(): PublicationError? {
    if (!isRestricted) return null
    val custom = FlutterReadiumRestrictions.customError(this)
    return custom?.let { PublicationError.Custom(it) } ?: PublicationError.Restricted(protectionError)
}
