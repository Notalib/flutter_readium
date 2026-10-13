package dk.nota.flutterreadium.models

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
internal class FlutterMediaOverlayTest {
    private fun parse(
        json: String,
        vararg toc: String,
    ): FlutterMediaOverlay =
        FlutterMediaOverlay.fromJson(
            JSONObject(json),
            position = 2,
            tocHref = null,
            title = "",
            readiumOrderItemDuration = 20.0,
            tocHrefs = toc.map { Url(it)!! },
        )!!

    private fun locator(
        href: String,
        vararg fragments: String,
    ) = Locator(Url(href)!!, MediaType.XHTML, locations = Locator.Locations(fragments = fragments.toList()))

    @Test
    fun audioLessParentOwnsNarratedChildren() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#section","narration":[
          {"text":"ch.xhtml#heading","audio":"ch.mp3#t=0,5"},
          {"text":"ch.xhtml#p1","audio":"ch.mp3#t=5,10"}
        ]}]}""",
                "ch.xhtml#section",
            )
        assertEquals(listOf("ch.xhtml#section", "ch.xhtml#section"), overlay.items.map { it.tocHref.toString() })
        assertEquals(listOf(2, 2), overlay.items.map { it.position })
    }

    @Test
    fun syntheticSubsectionHeadingContinuesOverParent() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#chapter","narration":[
          {"text":"ch.xhtml#intro","audio":"ch.mp3#t=0,5"},
          {"text":"ch.xhtml#sub","audio":"ch.mp3#t=5,10"},
          {"text":"ch.xhtml#p1","audio":"ch.mp3#t=10,15"}
        ]}]}""",
                "ch.xhtml#chapter",
                "ch.xhtml#sub",
            )
        assertEquals(listOf("ch.xhtml#chapter", "ch.xhtml#sub", "ch.xhtml#sub"), overlay.items.map { it.tocHref.toString() })
    }

    @Test
    fun flatHeadingContinuesInsideGenericWrapper() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#body","narration":[
          {"text":"ch.xhtml#heading","audio":"ch.mp3#t=0,5"},
          {"text":"ch.xhtml#p1","audio":"ch.mp3#t=5,10"}
        ]}]}""",
                "ch.xhtml#heading",
            )
        assertEquals(listOf("ch.xhtml#heading", "ch.xhtml#heading"), overlay.items.map { it.tocHref.toString() })
    }

    @Test
    fun boundaryPageUsesNextResourcesFileOnlyToc() {
        val overlay =
            parse(
                """{"narration":[{"text":"one.xhtml","narration":[
          {"text":"one.xhtml#p1","audio":"one.mp3#t=0,5"},
          {"text":"two.xhtml#page-3","audio":"two.mp3#t=0,1"}
        ]}]}""",
                "one.xhtml",
                "two.xhtml",
            )
        assertEquals(listOf("one.xhtml", "two.xhtml"), overlay.items.map { it.tocHref.toString() })
        assertEquals(0.0, overlay.items.last().audioStart!!, 0.001)
    }

    @Test
    fun unknownNextResourceDoesNotInheritPreviousSection() {
        val overlay =
            parse(
                """{"narration":[{"text":"one.xhtml#section","narration":[
          {"text":"one.xhtml#p1","audio":"one.mp3#t=0,5"},
          {"text":"two.xhtml#page-3","audio":"two.mp3#t=0,1"}
        ]}]}""",
                "one.xhtml#section",
            )
        assertEquals(
            "one.xhtml#section",
            overlay.items
                .first()
                .tocHref
                .toString(),
        )
        assertNull(overlay.items.last().tocHref)
    }

    @Test
    fun nestedListDoesNotReplaceCallersHeading() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#chapter","narration":[
          {"text":"ch.xhtml#sub","narration":[{"text":"ch.xhtml#p1","audio":"ch.mp3#t=0,5"}]},
          {"text":"ch.xhtml#p2","audio":"ch.mp3#t=5,10"}
        ]}]}""",
                "ch.xhtml#chapter",
                "ch.xhtml#sub",
            )
        assertEquals(listOf("ch.xhtml#sub", "ch.xhtml#chapter"), overlay.items.map { it.tocHref.toString() })
    }

    @Test
    fun knownSectionSeeksAfterEarlierCueWithFallbackDisabled() {
        val overlay =
            parse(
                """{"narration":[
          {"text":"ch.xhtml#intro","audio":"ch.mp3#t=0,5"},
          {"text":"ch.xhtml#section","narration":[{"text":"ch.xhtml#heading","audio":"ch.mp3#t=5,10"}]}
        ]}""",
                "ch.xhtml#section",
            )
        val item = overlay.findItemFromLocator(locator("ch.xhtml", "#section"), allowResourceFallback = false)
        assertEquals("heading", item?.textId)
        assertEquals(5.0, item!!.audioStart!!, 0.001)
        assertNull(overlay.findItemFromLocator(locator("ch.xhtml", "#unknown"), allowResourceFallback = false))
    }

    @Test
    fun repeatedAnchorsMatchTheActualTextResource() {
        val overlay =
            parse(
                """{"narration":[
          {"text":"one.xhtml#heading","audio":"one.mp3#t=0,5"},
          {"text":"two.xhtml#heading","audio":"two.mp3#t=0,5"}
        ]}""",
            )
        assertEquals("two.mp3", overlay.findItemFromLocator(locator("two.xhtml", "#heading"), allowResourceFallback = false)?.audioFile)
    }

    @Test
    fun explicitTimeWinsOverSectionAnchor() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#section","narration":[
          {"text":"ch.xhtml#p1","audio":"ch.mp3#t=0,5"},
          {"text":"ch.xhtml#p2","audio":"ch.mp3#t=5,10"}
        ]}]}""",
                "ch.xhtml#section",
            )
        assertEquals("p2", overlay.findItemFromLocator(locator("ch.xhtml", "#section", "t=5"), allowResourceFallback = false)?.textId)
    }

    @Test
    fun titleEnrichmentDoesNotReopenOwnershipWindow() {
        val overlay =
            parse(
                """{"narration":[
          {"text":"ch.xhtml#chapter","narration":[
            {"text":"ch.xhtml#sub","audio":"ch.mp3#t=0,5"},
            {"text":"ch.xhtml#p1","audio":"ch.mp3#t=5,10"}
          ]},
          {"text":"ch.xhtml#outside","audio":"ch.mp3#t=10,15"}
        ]}""",
                "ch.xhtml#chapter",
                "ch.xhtml#sub",
            )
        val enriched = overlay.withTocTitles(listOf(Link(Href("ch.xhtml#sub")!!, title = "Subsection")))
        assertEquals(listOf("ch.xhtml#sub", "ch.xhtml#sub", null), enriched.items.map { it.tocHref?.toString() })
        assertEquals(listOf("Subsection", "Subsection", ""), enriched.items.map { it.title })
    }

    @Test
    fun exactCueWinsOverEarlierOwnedCue() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#section","narration":[
          {"text":"ch.xhtml#p1","audio":"ch.mp3#t=0,5"},
          {"text":"ch.xhtml#section","audio":"ch.mp3#t=5,10"}
        ]}]}""",
                "ch.xhtml#section",
            )
        assertEquals(5.0, overlay.findItemFromLocator(locator("ch.xhtml", "#section"), allowResourceFallback = false)!!.audioStart!!, 0.001)
    }
}
