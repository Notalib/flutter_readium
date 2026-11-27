package dk.nota.flutterreadium

import dk.nota.flutterreadium.models.PageInformation
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.util.Url
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
internal class PageInformationTest {
    // optDouble turns JSON null into NaN, which must not reach the locator.
    @Test
    fun `null progressionEnd is left out of otherLocations`() {
        val info = PageInformation.fromJson("""{"progressionEnd":null}""", Url("chapter.xhtml")!!)

        assertFalse(info.otherLocations.containsKey("progressionEnd"))
    }
}
