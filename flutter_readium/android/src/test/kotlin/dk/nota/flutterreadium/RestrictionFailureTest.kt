package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.LocalizedString
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.protection.ContentProtection
import org.readium.r2.shared.publication.services.ContentProtectionService
import org.readium.r2.shared.publication.services.contentProtectionServiceFactory
import org.readium.r2.shared.util.Error
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
internal class RestrictionFailureTest {
    private class FakeProtection(
        override val isRestricted: Boolean,
        override val error: Error? = null,
    ) : ContentProtectionService {
        override val credentials: String? = null
        override val rights: ContentProtectionService.UserRights = ContentProtectionService.UserRights.AllRestricted
        override val scheme: ContentProtection.Scheme? = ContentProtection.Scheme.Lcp
    }

    private fun publication(
        protection: ContentProtectionService?,
        title: String = "Protected",
    ) = Publication(
        Manifest(metadata = Metadata(localizedTitle = LocalizedString(title))),
        servicesBuilder =
            Publication.ServicesBuilder().apply {
                if (protection != null) contentProtectionServiceFactory = { protection }
            },
    )

    @Test
    fun `unprotected publication is readable`() {
        assertNull(publication(null).restrictionFailure())
    }

    @Test
    fun `unlocked protected publication is readable`() {
        assertNull(publication(FakeProtection(isRestricted = false)).restrictionFailure())
    }

    @Test
    fun `restricted publication without a mapper fails as forbidden`() {
        val failure = publication(FakeProtection(isRestricted = true)).restrictionFailure()

        assertTrue(failure is PublicationError.Restricted)
        assertEquals("forbidden", failure?.wireCode)
    }

    @Test
    fun `restricted publication takes the wire code of a registered mapper`() {
        // Mappers are global, so this one only answers for its own publication.
        FlutterReadiumRestrictions.registerMapper { publication ->
            FlutterReadiumCustomError("testRestricted", "restricted").takeIf { publication.metadata.title == "Mapped" }
        }

        val failure = publication(FakeProtection(isRestricted = true), title = "Mapped").restrictionFailure()

        assertTrue(failure is PublicationError.Custom)
        assertEquals("testRestricted", failure?.wireCode)
    }
}
