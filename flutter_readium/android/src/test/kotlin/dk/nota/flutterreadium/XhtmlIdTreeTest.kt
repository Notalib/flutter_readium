package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
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

    @Test
    fun idsBeforeAParseErrorAreKept() {
        val tree = tree("""<section id="s1"><p id="p1">P &undefined; </p><p id="p2">Q</p></section>""")

        assertEquals("p1", tree.firstDescendant("s1", setOf("p1", "p2")))
    }
}
