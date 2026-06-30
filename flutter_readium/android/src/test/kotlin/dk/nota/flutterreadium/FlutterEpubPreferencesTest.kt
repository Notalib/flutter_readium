package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

@OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
internal class FlutterEpubPreferencesTest {
    @Test
    fun `fontSize is forwarded unchanged as a ratio`() {
        val prefs = FlutterEpubPreferences(fontSize = 1.5)
        val epub = prefs.toEpubPreferences()
        assertEquals(1.5, epub.fontSize)
    }

    @Test
    fun `fontSize default ratio (1_0) is preserved`() {
        val prefs = FlutterEpubPreferences(fontSize = 1.0)
        val epub = prefs.toEpubPreferences()
        assertEquals(1.0, epub.fontSize)
    }

    @Test
    fun `null fontSize produces null in EpubPreferences`() {
        val prefs = FlutterEpubPreferences(fontSize = null)
        val epub = prefs.toEpubPreferences()
        assertNull(epub.fontSize)
    }
}
