package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

internal class ReaderFontFamilyTest {
    @Test
    fun `fromList preserves family metadata and resolves face assets`() {
        val declarations =
            ReaderFontFamily.fromList(
                listOf(
                    mapOf(
                        "name" to "Atkinson Hyperlegible",
                        "fallbacks" to listOf("sans-serif"),
                        "faces" to
                            listOf(
                                mapOf("asset" to "fonts/regular.ttf", "style" to "normal", "weight" to 400),
                                mapOf("asset" to "fonts/bold-italic.ttf", "style" to "italic", "weight" to 700),
                            ),
                    ),
                ),
            ) { asset -> "flutter_assets/$asset" }

        assertEquals(1, declarations.size)
        assertEquals("Atkinson Hyperlegible", declarations.single().name)
        assertEquals(listOf("sans-serif"), declarations.single().fallbacks)
        assertEquals(
            listOf("flutter_assets/fonts/regular.ttf", "flutter_assets/fonts/bold-italic.ttf"),
            declarations.single().faces.map { it.asset },
        )
        assertEquals(listOf(ReaderFontStyle.NORMAL, ReaderFontStyle.ITALIC), declarations.single().faces.map { it.style })
        assertEquals(listOf(400, 700), declarations.single().faces.map { it.weight })
    }

    @Test
    fun `fromList rejects an unsupported style`() {
        assertThrows(IllegalArgumentException::class.java) {
            ReaderFontFamily.fromList(
                listOf(
                    mapOf(
                        "name" to "Invalid",
                        "faces" to listOf(mapOf("asset" to "font.ttf", "style" to "oblique")),
                    ),
                ),
            ) { it }
        }
    }
}
