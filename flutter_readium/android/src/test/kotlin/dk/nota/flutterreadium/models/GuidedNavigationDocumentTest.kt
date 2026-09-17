package dk.nota.flutterreadium.models

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guided Navigation across the content modalities the plugin ships.
 *
 * Each modality authors its cues differently, and requiring a `textref` silently dropped every
 * cue of a DiViNa comic, which references the page image instead of a text document.
 */
internal class GuidedNavigationDocumentTest {
    private fun documentOf(vararg objects: String): GuidedNavigationDocument =
        GuidedNavigationDocument.fromJSON(
            JSONObject("""{"guided":[${objects.joinToString(",")}]}"""),
        )!!

    private fun itemsOf(document: GuidedNavigationDocument): List<FlutterMediaOverlayItem> =
        document.toMediaOverlays(position = 1, title = "Side 1").flatMap { it.items }

    @Test
    fun divinaCue_withImgrefOnly_becomesAnItemAnchoredToThePageImage() {
        val items =
            itemsOf(
                documentOf(
                    """{"role":["section"],"children":[
                        {"imgref":"image0001.jpg#xywh=pixel:44,113,757,226","audioref":"02_side_1.mp3#t=0,12.5"}
                    ]}""",
                ),
            )

        assertEquals(1, items.size)
        assertEquals("image0001.jpg", items[0].textFile)
        assertEquals("02_side_1.mp3", items[0].audioFile)
        assertEquals(0.0, items[0].audioStart!!, 0.0001)
        assertEquals(12.5, items[0].audioEnd!!, 0.0001)
    }

    @Test
    fun divinaCue_dropsThePanelBox_soItIsNotPublishedAsACssSelector() {
        val items =
            itemsOf(
                documentOf(
                    """{"children":[
                        {"imgref":"image0001.jpg#xywh=pixel:44,113,757,226","audioref":"a.mp3#t=0,1"}
                    ]}""",
                ),
            )

        assertEquals("", items[0].textId)
    }

    @Test
    fun comicCue_withBothRefs_keepsTheTextDocument() {
        val items =
            itemsOf(
                documentOf(
                    """{"children":[
                        {"textref":"page1.xhtml#panel1","imgref":"image0001.jpg#xywh=pixel:10,20,30,40","audioref":"page1.mp3#t=0,5"}
                    ]}""",
                ),
            )

        assertEquals("page1.xhtml", items[0].textFile)
        assertEquals("panel1", items[0].textId)
    }

    @Test
    fun epubCue_withTextrefOnly_isUnchanged() {
        val items =
            itemsOf(
                documentOf(
                    """{"textref":"chapter2.xhtml#p1","audioref":"chapter2.mp3#t=0,10"}""",
                    """{"textref":"chapter2.xhtml#p2","audioref":"chapter2.mp3#t=10,20"}""",
                ),
            )

        assertEquals(2, items.size)
        assertEquals(listOf("p1", "p2"), items.map { it.textId })
    }

    @Test
    fun cueWithoutAudio_isSkipped() {
        val items = itemsOf(documentOf("""{"children":[{"imgref":"image0001.jpg"}]}"""))

        assertTrue(items.isEmpty())
    }

    @Test
    fun cueWithoutAnyVisualReference_isSkipped() {
        val items = itemsOf(documentOf("""{"children":[{"audioref":"a.mp3#t=0,5"}]}"""))

        assertTrue(items.isEmpty())
    }

    @Test
    fun cuesAreGroupedByAudioAndTextFilePair() {
        val overlays =
            documentOf(
                """{"children":[
                    {"imgref":"image0001.jpg","audioref":"02_side_1.mp3#t=0,5"},
                    {"imgref":"image0001.jpg","audioref":"02_side_1.mp3#t=5,10"},
                    {"imgref":"image0002.jpg","audioref":"03_side_2.mp3#t=0,5"}
                ]}""",
            ).toMediaOverlays(position = 1, title = "Side 1")

        assertEquals(2, overlays.size)
        assertEquals(2, overlays[0].items.size)
        assertEquals(1, overlays[1].items.size)
    }
}
