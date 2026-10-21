package dk.nota.flutterreadium.models

import dk.nota.flutterreadium.XhtmlIdTree
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
    fun xhtmlBoundaryEndsHeadingContinuationBeforeOwnershipLookup() {
        val overlay =
            parse(
                """{"narration":[
          {"text":"ch.xhtml#h","audio":"ch.mp3#t=0,5"},
          {"text":"ch.xhtml#p1","audio":"ch.mp3#t=5,10"},
          {"text":"ch.xhtml#p2","audio":"ch.mp3#t=10,15"},
          {"text":"ch.xhtml#p3","audio":"ch.mp3#t=15,20"}
        ]}""",
                "ch.xhtml#s1",
                "ch.xhtml#h",
                "ch.xhtml#side",
                "ch.xhtml#s2",
            )
        val tree =
            XhtmlIdTree(
                """<html><body><section id="s1"><h2 id="h"/><p id="p1"/>
          <aside id="side"><p id="p2"/></aside></section><section id="s2"><p id="p3"/></section></body></html>""".toByteArray(),
            )
        val toc = listOf("s1", "h", "side", "s2").map { Link(Href("ch.xhtml#$it")!!, title = it) }
        val corrected = overlay.withTocBoundaries(toc, mapOf("ch.xhtml" to tree))
        assertEquals(listOf("ch.xhtml#h", "ch.xhtml#h", "ch.xhtml#side", "ch.xhtml#s2"), corrected.items.map { it.tocHref.toString() })
        assertEquals(15.0, corrected.findItemFromTocHref(Url("ch.xhtml")!!, "s2")?.audioStart)
        assertEquals(0.0, corrected.findItemFromTocHref(Url("ch.xhtml")!!, "h")?.audioStart)
        assertEquals(overlay, overlay.withTocBoundaries(toc, emptyMap()))
    }

    @Test
    fun xhtmlBoundaryPreservesRepresentedNestedContainerCallerScope() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#h","audio":"ch.mp3#t=0,5"},
          {"text":"ch.xhtml#side","narration":[{"text":"ch.xhtml#p2","audio":"ch.mp3#t=5,10"}]},
          {"text":"ch.xhtml#p3","audio":"ch.mp3#t=10,15"}]}""",
                "ch.xhtml#h",
                "ch.xhtml#side",
            )
        val tree = XhtmlIdTree("""<html><body><h2 id="h"/><aside id="side"><p id="p2"/><p id="p3"/></aside></body></html>""".toByteArray())
        val toc = listOf("h", "side").map { Link(Href("ch.xhtml#$it")!!) }
        assertEquals(
            listOf("ch.xhtml#h", "ch.xhtml#side", "ch.xhtml#h"),
            overlay.withTocBoundaries(toc, mapOf("ch.xhtml" to tree)).items.map { it.tocHref.toString() },
        )
    }

    @Test
    fun guidedFlatCuesWithLastMatchedHeadingUseTheSameXhtmlBoundaryCorrection() {
        val guided =
            GuidedNavigationDocument.fromJSON(
                JSONObject(
                    """{"guided":[
          {"textref":"ch.xhtml#h","audioref":"ch.mp3#t=0,5"},
          {"textref":"ch.xhtml#p1","audioref":"ch.mp3#t=5,10"},
          {"textref":"ch.xhtml#p2","audioref":"ch.mp3#t=10,15"}]}""",
                ),
            )!!
        val overlay =
            guided.toMediaOverlays().single().copy(
                items =
                    guided.toMediaOverlays().single().items.map {
                        it.copy(tocHref = Url("ch.xhtml#h"), title = "Detail")
                    },
            )
        val tree =
            XhtmlIdTree(
                """<html><body><section id="s1"><h2 id="h"/><p id="p1"/></section>
          <section id="s2"><p id="p2"/></section></body></html>""".toByteArray(),
            )
        val toc = listOf("s1", "h", "s2").map { Link(Href("ch.xhtml#$it")!!) }
        val corrected = overlay.withTocBoundaries(toc, mapOf("ch.xhtml" to tree))
        assertEquals(listOf("ch.xhtml#h", "ch.xhtml#h", "ch.xhtml#s2"), corrected.items.map { it.tocHref.toString() })
        assertEquals(10.0, corrected.findItemFromTocHref(Url("ch.xhtml")!!, "s2")?.audioStart)
    }

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

    @Test
    fun activeHeadingSurvivesMatchingNestedContainer() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#parent","narration":[
  {"text":"ch.xhtml#A","audio":"ch.mp3#t=0,5"},
  {"text":"ch.xhtml#B","narration":[{"text":"ch.xhtml#inside","audio":"ch.mp3#t=5,10"}]},
  {"text":"ch.xhtml#after","audio":"ch.mp3#t=10,15"}
]}]}""",
                "ch.xhtml#parent",
                "ch.xhtml#A",
                "ch.xhtml#B",
            )
        assertEquals(listOf("ch.xhtml#A", "ch.xhtml#B", "ch.xhtml#A"), overlay.items.map { it.tocHref?.toString() })
    }

    @Test
    fun activeHeadingSurvivesGenericWrapperHeading() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#parent","narration":[
  {"text":"ch.xhtml#A","audio":"ch.mp3#t=0,5"},
  {"narration":[{"text":"ch.xhtml#B","audio":"ch.mp3#t=5,10"},{"text":"ch.xhtml#inside","audio":"ch.mp3#t=10,15"}]},
  {"text":"ch.xhtml#after","audio":"ch.mp3#t=15,20"}
]}]}""",
                "ch.xhtml#parent",
                "ch.xhtml#A",
                "ch.xhtml#B",
            )
        assertEquals(listOf("ch.xhtml#A", "ch.xhtml#B", "ch.xhtml#B", "ch.xhtml#A"), overlay.items.map { it.tocHref?.toString() })
    }

    @Test
    fun ownAudioAndChildrenPreserveOrderAndCallersActiveHeading() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#parent","narration":[
  {"text":"ch.xhtml#A","audio":"ch.mp3#t=0,5"},
  {"text":"ch.xhtml#B","audio":"ch.mp3#t=5,10","narration":[{"text":"ch.xhtml#inside","audio":"ch.mp3#t=10,15"}]},
  {"text":"ch.xhtml#after","audio":"ch.mp3#t=15,20"}
]}]}""",
                "ch.xhtml#parent",
                "ch.xhtml#A",
                "ch.xhtml#B",
            )
        assertEquals(listOf("ch.xhtml#A", "ch.xhtml#B", "ch.xhtml#B", "ch.xhtml#A"), overlay.items.map { it.tocHref?.toString() })
        assertEquals(listOf("A", "B", "inside", "after"), overlay.items.map { it.textId })
        assertEquals(listOf(0.0, 5.0, 10.0, 15.0), overlay.items.map { it.audioStart })
    }

    @Test
    fun duplicateStructuralIdsMatchSecondResourceWithoutExactCue() {
        val overlay =
            parse(
                """{"narration":[
  {"text":"one.xhtml#section","narration":[{"text":"one.xhtml#p1","audio":"one.mp3#t=0,5"}]},
  {"text":"two.xhtml#section","narration":[{"text":"two.xhtml#p2","audio":"two.mp3#t=7,12"}]}
]}""",
                "one.xhtml#section",
                "two.xhtml#section",
            )
        val item = overlay.findItemFromLocator(locator("two.xhtml", "#section"), allowResourceFallback = false)
        assertEquals("p2", item?.textId)
        assertEquals("two.mp3", item?.audioFile)
        assertEquals(7.0, item!!.audioStart!!, 0.001)
    }

    @Test
    fun audioLessFlatHeadingDoesNotActivateContinuation() {
        val overlay = parse("""{"narration":[{"text":"ch.xhtml#A"},{"text":"ch.xhtml#after","audio":"ch.mp3#t=0,5"}]}""", "ch.xhtml#A")
        assertEquals(1, overlay.items.size)
        assertNull(overlay.items.first().tocHref)
    }

    @Test
    fun noTocDoesNotFabricateOwnership() {
        val overlay = parse("""{"narration":[{"text":"ch.xhtml#p1","audio":"ch.mp3#t=0,5"}]}""")
        assertEquals(1, overlay.items.size)
        assertNull(overlay.items.first().tocHref)
    }

    @Test
    fun emptyNarrationAndInvalidCueFieldsEmitNoItems() {
        assertEquals(emptyList<FlutterMediaOverlayItem>(), parse("""{"narration":[]}""").items)
        assertEquals(
            emptyList<FlutterMediaOverlayItem>(),
            parse("""{"narration":[{},{"text":"ch.xhtml#p1"},{"text":"ch.xhtml#p2","audio":""},{"audio":"ch.mp3#t=0,5"}]}""").items,
        )
    }

    @Test
    fun invalidRootNarrationIsRejected() {
        for (json in listOf("{}", """{"narration":"invalid"}""", """{"narration":null}""")) {
            assertNull(FlutterMediaOverlay.fromJson(JSONObject(json), 0, null, "", 20.0))
        }
    }

    @Test(expected = org.json.JSONException::class)
    fun nonObjectNarrationEntryRetainsJsonRejection() {
        parse("""{"narration":[null]}""")
    }

    @Test
    fun resourceFallbackRemainsGatedAndWrongResourceIsRejected() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#p1","audio":"first.mp3#t=0,5"},{"text":"ch.xhtml#p2","audio":"second.mp3#t=10,15"}]}""",
            )
        for (fragments in listOf(emptyArray(), arrayOf("#unknown"))) {
            val allowed = overlay.findItemFromLocator(locator("ch.xhtml", *fragments), allowResourceFallback = true)
            assertEquals("first.mp3", allowed?.audioFile)
            assertEquals(0.0, allowed!!.audioStart!!, 0.001)
            assertNull(overlay.findItemFromLocator(locator("ch.xhtml", *fragments), allowResourceFallback = false))
        }
        assertNull(overlay.findItemFromLocator(locator("unknown.xhtml", "#p1"), allowResourceFallback = true))
    }

    @Test
    fun explicitTimeGapSelectsNextCueAndAfterLastReturnsNoMatch() {
        val overlay =
            parse(
                """{"narration":[{"text":"ch.xhtml#p1","audio":"first.mp3#t=0,5"},{"text":"ch.xhtml#p2","audio":"second.mp3#t=10,15"}]}""",
            )
        for (href in listOf("ch.xhtml", "second.mp3")) {
            val item = overlay.findItemFromLocator(locator(href, "#p1", "t=7"), allowResourceFallback = false)
            assertEquals("second.mp3", item?.audioFile)
            assertEquals(10.0, item!!.audioStart!!, 0.001)
            assertNull(overlay.findItemFromLocator(locator(href, "#p1", "t=20"), allowResourceFallback = true))
        }
    }

    @Test
    fun exactAudioBoundarySelectsStartingCue() {
        val overlay =
            parse(
                """{"narration":[{"text":"one.xhtml#ending","audio":"track.mp3#t=14,16"},{"text":"two.xhtml#starting","audio":"track.mp3#t=16,18"}]}""",
            )
        assertEquals("starting", overlay.findItemInRange("track.mp3", 16.0)?.textId)
        assertEquals("starting", overlay.findItemFromLocator(locator("track.mp3", "t=16"), allowResourceFallback = false)?.textId)
        assertNull(overlay.findItemInRange("track.mp3", 18.0))
    }
}
