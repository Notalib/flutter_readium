package dk.nota.flutterreadium

import dk.nota.flutterreadium.models.guidedNavigationMediaType
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.LocalizedString
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
internal class GuidedNavigationDetectionTest {
    private val chapter = Link(Href("chapter1.xhtml")!!, mediaType = MediaType.XHTML)
    private val audio = Link(Href("chapter1.mp3")!!, mediaType = MediaType.MP3)

    private fun guidedNavigationEbook(
        readingOrder: List<Link> = listOf(chapter),
        resources: List<Link> = emptyList(),
    ) =
        Publication(
            Manifest(
                metadata =
                    Metadata(
                        localizedTitle = LocalizedString("Guided navigation publication"),
                        conformsTo = setOf(Publication.Profile.EPUB),
                    ),
                links = listOf(Link(Href("guided-navigation.json")!!, mediaType = guidedNavigationMediaType)),
                readingOrder = readingOrder,
                resources = resources,
            ),
        )

    @Test
    fun guidedNavigationLinkWithAudioResourcesIsDetected() {
        val publication = guidedNavigationEbook(resources = listOf(audio))

        assertTrue(publication.hasGuidedNavigationMediaOverlays())
    }

    @Test
    fun guidedNavigationLinkWithAudioAlternateIsDetected() {
        val publication = guidedNavigationEbook(readingOrder = listOf(chapter.copy(alternates = listOf(audio))))

        assertTrue(publication.hasGuidedNavigationMediaOverlays())
    }

    @Test
    fun guidedNavigationLinkWithoutAudioResourcesIsIgnored() {
        val image = Link(Href("page01.jpg")!!, mediaType = MediaType.JPEG)
        val publication = guidedNavigationEbook(resources = listOf(image))

        assertFalse(publication.hasGuidedNavigationMediaOverlays())
    }
}
