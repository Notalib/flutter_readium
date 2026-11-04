package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
internal class XhtmlIdTreeTest {
    private fun tree(body: String) =
        XhtmlIdTree(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
            <head><title>t</title></head>
            <body>$body</body>
            </html>
            """.trimIndent().toByteArray(),
        )

    /**
     * `boundaryOwner` returns the index of the ToC id that replaces a cue's current owner, or null to keep the owner.
     * Only an element that encloses the cue and starts after the owner's element can replace it.
     */
    @Test
    fun boundaryPreservesHeadingContinuationAndCallerScope() {
        // Given: section `s1` holds heading `h1`, paragraph `p1`, and aside `a1`, which contains `p2`.
        val tree = tree("""<section id="s1"><h2 id="h1"/><p id="p1"/><aside id="a1"><p id="p2"/></aside></section>""")
        val ids = listOf("s1", "h1", "a1")
        // Then: `p1` follows heading `h1` in the same section, so the heading keeps it.
        assertNull(tree.boundaryOwner("p1", "h1", ids))
        // Then: `a1` encloses `p2` and starts after `h1`, so `a1` (index 2) takes over.
        assertEquals(2, tree.boundaryOwner("p2", "h1", ids))
        // Then: the owner `s1` already encloses `p1`, so no later boundary applies.
        assertNull(tree.boundaryOwner("p1", "s1", ids))
        // Then: unknown ids and cues without an owner are left alone.
        assertNull(tree.boundaryOwner("p2", "missing", ids))
        assertNull(tree.boundaryOwner("missing", "h1", ids))
        assertNull(tree.boundaryOwner("p1", null, listOf("h1")))
    }

    @Test
    fun containerMapsToItsFirstContentDescendant() {
        val tree =
            tree(
                """
                <section id="s1"><div><h1 id="h1">H</h1></div><p id="p1">P</p>
                  <aside id="a1"><span id="x">X</span><p id="p2">P</p></aside>
                </section>
                """,
            )
        val content = setOf("h1", "p1", "p2")

        assertEquals("h1", tree.firstDescendant("s1", content))
        assertEquals("p2", tree.firstDescendant("a1", content))
    }

    @Test
    fun emptyOrMissingIdHasNoDescendant() {
        val tree = tree("""<section id="s1"><div id="d"/></section><p id="p1">P</p>""")

        assertNull(tree.firstDescendant("s1", setOf("p1")))
        assertNull(tree.firstDescendant("missing", setOf("p1")))
    }

    @Test
    fun elementDoesNotMatchItself() {
        val tree = tree("""<p id="p1">P</p>""")

        assertNull(tree.firstDescendant("p1", setOf("p1")))
    }

    private fun locator(fragments: List<String> = listOf("empty")) =
        Locator(
            href = Url("page.xhtml")!!,
            mediaType = MediaType.XHTML,
            title = "Heading",
            locations =
                Locator.Locations(
                    fragments = fragments,
                    progression = 0.4,
                    position = 3,
                    otherLocations = mapOf("custom" to "preserved"),
                ),
        )

    @Test
    fun anchorRewritesToFirstCueAtOrAfterElementAndPreservesMetadata() {
        val tree = tree("""<h1 id="empty"/><section><p id="p1"/></section>""")
        val input = locator()
        val result = tree.anchor(input, "empty", setOf("p1"))!!
        assertEquals(listOf("p1"), result.locations.fragments)
        assertEquals("#p1", result.locations.otherLocations["cssSelector"])
        assertEquals("preserved", result.locations.otherLocations["custom"])
        assertEquals(input.href, result.href)
        assertEquals(input.title, result.title)
        assertEquals(0.4, result.locations.progression)
        assertEquals(3, result.locations.position)
        assertEquals(listOf("empty"), input.locations.fragments)
    }

    @Test
    fun unknownAnchorKeepsFallbackAndKnownElementAfterLastCueHasNoMatch() {
        val tree = tree("""<p id="p1"/><h1 id="empty"/>""")
        assertEquals(locator(), tree.anchor(locator(), "missing", setOf("p1")))
        assertNull(tree.anchor(locator(), "empty", setOf("p1")))
    }

    @Test
    fun anchorPreservesExplicitTime() {
        val input = locator(listOf("empty", "t=2.5"))
        assertEquals(input, tree("""<h1 id="empty"/><p id="p1"/>""").anchor(input, "empty", setOf("p1")))
    }

    @Test
    fun undeclaredHtmlEntityLeavesLaterAnchorsUnknown() {
        val tree = tree("""<p id="before">x&nbsp;</p><section id="empty"><p id="p1"/></section>""")
        assertEquals(listOf("before"), tree.ids)
        assertEquals(locator(), tree.anchor(locator(), "empty", setOf("p1")))
    }

    @Test
    fun numericEntityAllowsLaterAnchorsToBeIndexed() {
        val tree = tree("""<p id="before">x&#160;</p><section id="empty"><p id="p1"/></section>""")
        assertEquals(listOf("before", "empty", "p1"), tree.ids)
        assertEquals(listOf("p1"), tree.anchor(locator(), "empty", setOf("p1"))!!.locations.fragments)
    }

    @Test
    fun idsBeforeAParseErrorAreKept() {
        val tree = tree("""<section id="s1"><p id="p1">P &undefined; </p><p id="p2">Q</p></section>""")

        assertEquals("p1", tree.firstDescendant("s1", setOf("p1", "p2")))
    }
}
