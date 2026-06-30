package dk.nota.flutterreadium

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

internal class ReadiumReaderMOBreakPolicyTest {
    @Test
    fun shouldInjectMOColumnBreakCss_returnsTrue_onlyWhenMOActiveAndPreferenceEnabled() {
        assertTrue(shouldInjectMOColumnBreakCss(isMOActive = true, preventMOColumnBreaks = true))
        assertFalse(shouldInjectMOColumnBreakCss(isMOActive = true, preventMOColumnBreaks = false))
        assertFalse(shouldInjectMOColumnBreakCss(isMOActive = false, preventMOColumnBreaks = true))
        assertFalse(shouldInjectMOColumnBreakCss(isMOActive = false, preventMOColumnBreaks = false))
    }
}
