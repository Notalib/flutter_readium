package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

// Document: <section id="sec"><h1 id="h"/><p id="p1"/><aside id="side"><p id="p2"/></aside></section>
//           <section id="sec2"><p id="p3"/></section><section id="empty"/>
internal class TocEntryIndexTest {
    private val content = listOf("#h", "#p1", "#p2", "#p3")
    private val anchors = mapOf("#sec" to "#h", "#side" to "#p2", "#sec2" to "#p3")

    private fun owner(
        cssSelector: String,
        vararg toc: String,
    ) = tocEntryIndexFor(cssSelector, content, toc.toList(), anchors)

    @Test
    fun uncuedTargetsOwnCuesFromTheirFirstContentDescendant() {
        assertEquals(0, owner("#h", "#sec", "#side", "#sec2"))
        assertEquals(0, owner("#p1", "#sec", "#side", "#sec2"))
        assertEquals(1, owner("#p2", "#sec", "#side", "#sec2"))
        assertEquals(2, owner("#p3", "#sec", "#side", "#sec2"))
    }

    @Test
    fun deeperEntryWinsASharedStart() {
        assertEquals(1, owner("#h", "#sec", "#h"))
        assertEquals(1, owner("#p1", "#sec", "#h"))
    }

    @Test
    fun cueBeforeEveryEntryGetsTheFirstEntry() {
        assertEquals(0, owner("#h", "#side", "#sec2"))
    }

    @Test
    fun fileOnlyEntryOwnsCuesBeforeTheFirstAnchoredEntry() {
        assertEquals(0, owner("#h", "#null", "#p2"))
        assertEquals(1, owner("#p3", "#null", "#p2"))
    }

    @Test
    fun unresolvedEntryLateInTheTocDoesNotOwnLaterCues() {
        assertEquals(0, owner("#p3", "#sec", "#empty"))
    }

    @Test
    fun unknownSelectorIsTreatedAsTheDocumentStart() {
        assertEquals(0, owner("#missing", "#sec", "#sec2"))
    }

    @Test
    fun noTocEntriesGiveNoOwner() {
        assertNull(owner("#p1"))
    }
}
