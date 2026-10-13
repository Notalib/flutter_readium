package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.readium.r2.navigator.preferences.Axis

@OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
internal class FlutterPdfPreferencesTest {
    private fun pdfium(layout: String?) =
        FlutterPdfPreferences
            .fromMap(if (layout == null) emptyMap() else mapOf("layout" to layout))
            .toPdfiumPreferences()

    @Test
    fun `paginated maps to scroll false without an axis`() {
        val prefs = pdfium("paginated")
        assertEquals(false, prefs.scroll)
        assertNull(prefs.scrollAxis)
    }

    @Test
    fun `scrollHorizontal maps to scroll true with horizontal axis`() {
        val prefs = pdfium("scrollHorizontal")
        assertEquals(true, prefs.scroll)
        assertEquals(Axis.HORIZONTAL, prefs.scrollAxis)
    }

    @Test
    fun `scrollVertical maps to scroll true with vertical axis`() {
        val prefs = pdfium("scrollVertical")
        assertEquals(true, prefs.scroll)
        assertEquals(Axis.VERTICAL, prefs.scrollAxis)
    }

    @Test
    fun `missing or unknown layout leaves scroll and axis unset`() {
        for (layout in listOf(null, "unknown")) {
            val prefs = pdfium(layout)
            assertNull(prefs.scroll)
            assertNull(prefs.scrollAxis)
        }
    }
}
