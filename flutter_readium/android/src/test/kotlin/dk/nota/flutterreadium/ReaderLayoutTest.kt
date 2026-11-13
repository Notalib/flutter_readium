package dk.nota.flutterreadium

import android.view.View
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
internal class ReaderLayoutTest {
    private fun layout(expose: Boolean) = ReaderLayout(RuntimeEnvironment.getApplication(), null, expose)

    @Test
    fun exposedLayoutStaysImportantWhenFlutterSetsAuto() {
        val layout = layout(expose = true)
        // Flutter's AccessibilityBridge does this each time it links the platform view.
        layout.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_AUTO
        assertTrue(layout.isImportantForAccessibility)
    }

    @Test
    fun exposedLayoutHidesWhenFlutterRemovesItFromSemantics() {
        val layout = layout(expose = true)
        layout.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        assertFalse(layout.isImportantForAccessibility)
    }

    @Test
    fun hiddenLayoutHidesDescendantsWhateverFlutterSets() {
        val layout = layout(expose = false)
        layout.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_AUTO
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS, layout.importantForAccessibility)
        assertFalse(layout.isImportantForAccessibility)
    }
}
