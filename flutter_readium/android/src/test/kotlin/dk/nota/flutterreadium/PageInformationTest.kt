package dk.nota.flutterreadium

import dk.nota.flutterreadium.models.PageInformation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.util.Url
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
internal class PageInformationTest {
    private val href = Url("chapter.xhtml")!!

    @Test
    fun `progressionEnd from the helper reaches otherLocations`() {
        val info = PageInformation.fromJson("""{"progressionEnd":0.45}""", href)

        assertEquals(0.45, info.otherLocations["progressionEnd"] as Double, 0.0)
    }

    @Test
    fun `integer progressionEnd is read as a double`() {
        val info = PageInformation.fromJson("""{"progressionEnd":1}""", href)

        assertEquals(1.0, info.otherLocations["progressionEnd"] as Double, 0.0)
    }

    @Test
    fun `null or missing progressionEnd is left out of otherLocations`() {
        assertFalse(PageInformation.fromJson("""{"progressionEnd":null}""", href).otherLocations.containsKey("progressionEnd"))
        assertFalse(PageInformation.fromJson("""{}""", href).otherLocations.containsKey("progressionEnd"))
    }
}
